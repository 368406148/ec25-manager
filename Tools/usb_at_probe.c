#include <libusb-1.0/libusb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void print_libusb_error(const char *what, int rc) {
    fprintf(stderr, "%s: %s (%d)\n", what, libusb_error_name(rc), rc);
}

static int endpoint_in(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_IN;
}

static int endpoint_out(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT;
}

static int endpoint_bulk(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK;
}

static void dump_config(libusb_device *dev) {
    struct libusb_config_descriptor *config = NULL;
    int rc = libusb_get_active_config_descriptor(dev, &config);
    if (rc != 0) {
        print_libusb_error("get active config", rc);
        return;
    }

    printf("interfaces: %d\n", config->bNumInterfaces);
    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface *iface = &config->interface[i];
        for (int a = 0; a < iface->num_altsetting; a++) {
            const struct libusb_interface_descriptor *alt = &iface->altsetting[a];
            printf("if=%u alt=%u class=0x%02x subclass=0x%02x proto=0x%02x endpoints=%u\n",
                   alt->bInterfaceNumber, alt->bAlternateSetting, alt->bInterfaceClass,
                   alt->bInterfaceSubClass, alt->bInterfaceProtocol, alt->bNumEndpoints);
            for (int e = 0; e < alt->bNumEndpoints; e++) {
                const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                printf("  ep=0x%02x attr=0x%02x maxPacket=%u\n",
                       ep->bEndpointAddress, ep->bmAttributes, ep->wMaxPacketSize);
            }
        }
    }
    libusb_free_config_descriptor(config);
}

static int test_interface(libusb_device_handle *handle, int ifnum, unsigned char ep_out, unsigned char ep_in) {
    int rc = libusb_claim_interface(handle, ifnum);
    if (rc != 0) {
        printf("if=%d claim failed: %s (%d)\n", ifnum, libusb_error_name(rc), rc);
        return 0;
    }

    const char *cmd = "AT\r";
    int transferred = 0;
    rc = libusb_bulk_transfer(handle, ep_out, (unsigned char *)cmd, (int)strlen(cmd), &transferred, 1000);
    if (rc != 0) {
        printf("if=%d write ep=0x%02x failed: %s (%d)\n", ifnum, ep_out, libusb_error_name(rc), rc);
        libusb_release_interface(handle, ifnum);
        return 0;
    }

    usleep(200000);

    unsigned char buffer[512];
    memset(buffer, 0, sizeof(buffer));
    rc = libusb_bulk_transfer(handle, ep_in, buffer, sizeof(buffer) - 1, &transferred, 1000);
    if (rc == 0 && transferred > 0) {
        printf("if=%d epOut=0x%02x epIn=0x%02x response (%d bytes):\n%s\n",
               ifnum, ep_out, ep_in, transferred, buffer);
        libusb_release_interface(handle, ifnum);
        return strstr((char *)buffer, "OK") != NULL || strstr((char *)buffer, "AT") != NULL;
    }

    printf("if=%d read ep=0x%02x: %s (%d), bytes=%d\n",
           ifnum, ep_in, libusb_error_name(rc), rc, transferred);
    libusb_release_interface(handle, ifnum);
    return 0;
}

int main(int argc, char **argv) {
    uint16_t vid = 0x2c7c;
    uint16_t pid = 0x0125;
    if (argc == 3) {
        vid = (uint16_t)strtol(argv[1], NULL, 16);
        pid = (uint16_t)strtol(argv[2], NULL, 16);
    }

    libusb_context *ctx = NULL;
    int rc = libusb_init(&ctx);
    if (rc != 0) {
        print_libusb_error("libusb init", rc);
        return 1;
    }

    libusb_device **list = NULL;
    ssize_t count = libusb_get_device_list(ctx, &list);
    if (count < 0) {
        print_libusb_error("get device list", (int)count);
        libusb_exit(ctx);
        return 1;
    }

    libusb_device *target = NULL;
    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor desc;
        if (libusb_get_device_descriptor(list[i], &desc) == 0 &&
            desc.idVendor == vid && desc.idProduct == pid) {
            target = list[i];
            break;
        }
    }

    if (!target) {
        fprintf(stderr, "device %04x:%04x not found\n", vid, pid);
        libusb_free_device_list(list, 1);
        libusb_exit(ctx);
        return 2;
    }

    printf("found device %04x:%04x\n", vid, pid);
    dump_config(target);

    libusb_device_handle *handle = NULL;
    rc = libusb_open(target, &handle);
    if (rc != 0) {
        print_libusb_error("open device", rc);
        libusb_free_device_list(list, 1);
        libusb_exit(ctx);
        return 3;
    }

    struct libusb_config_descriptor *config = NULL;
    rc = libusb_get_active_config_descriptor(target, &config);
    if (rc != 0) {
        print_libusb_error("get active config", rc);
        libusb_close(handle);
        libusb_free_device_list(list, 1);
        libusb_exit(ctx);
        return 4;
    }

    int matched = 0;
    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface_descriptor *alt = &config->interface[i].altsetting[0];
        unsigned char ep_in = 0;
        unsigned char ep_out = 0;
        for (int e = 0; e < alt->bNumEndpoints; e++) {
            const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
            if (!endpoint_bulk(ep)) continue;
            if (endpoint_in(ep)) ep_in = ep->bEndpointAddress;
            if (endpoint_out(ep)) ep_out = ep->bEndpointAddress;
        }
        if (ep_in && ep_out) {
            matched |= test_interface(handle, alt->bInterfaceNumber, ep_out, ep_in);
        }
    }

    libusb_free_config_descriptor(config);
    libusb_close(handle);
    libusb_free_device_list(list, 1);
    libusb_exit(ctx);

    return matched ? 0 : 5;
}
