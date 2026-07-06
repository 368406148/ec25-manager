#include "CEC25USB.h"

#include <libusb-1.0/libusb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>

struct ec25_usb_session {
    libusb_context *context;
    libusb_device_handle *handle;
    int interface_number;
    unsigned char endpoint_in;
    unsigned char endpoint_out;
    char description[160];
};

static void set_error(char *error, size_t error_len, const char *message) {
    if (!error || error_len == 0) return;
    snprintf(error, error_len, "%s", message ? message : "unknown error");
}

static void set_libusb_error(char *error, size_t error_len, const char *prefix, int rc) {
    if (!error || error_len == 0) return;
    snprintf(error, error_len, "%s: %s (%d)", prefix, libusb_error_name(rc), rc);
}

static long long now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (long long)tv.tv_sec * 1000LL + (long long)tv.tv_usec / 1000LL;
}

static int endpoint_bulk(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK;
}

static int endpoint_in(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_IN;
}

static int endpoint_out(const struct libusb_endpoint_descriptor *ep) {
    return (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT;
}

static void drain_endpoint(libusb_device_handle *handle, unsigned char endpoint_in) {
    unsigned char buffer[512];
    int transferred = 0;
    for (int i = 0; i < 16; i++) {
        int rc = libusb_bulk_transfer(handle, endpoint_in, buffer, sizeof(buffer), &transferred, 20);
        if (rc != 0 || transferred <= 0) return;
    }
}

static int append_text(char **text, size_t *length, size_t *capacity, const char *line) {
    size_t line_len = strlen(line);
    size_t need = *length + line_len + 2;
    if (need > *capacity) {
        size_t next_capacity = *capacity == 0 ? 512 : *capacity * 2;
        while (next_capacity < need) next_capacity *= 2;
        char *next = realloc(*text, next_capacity);
        if (!next) return -1;
        *text = next;
        *capacity = next_capacity;
    }
    if (*length > 0) {
        (*text)[(*length)++] = '\n';
    }
    memcpy(*text + *length, line, line_len);
    *length += line_len;
    (*text)[*length] = '\0';
    return 0;
}

static void trim_line(char *line) {
    char *start = line;
    while (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n') start++;
    if (start != line) memmove(line, start, strlen(start) + 1);
    size_t len = strlen(line);
    while (len > 0 && (line[len - 1] == ' ' || line[len - 1] == '\t' || line[len - 1] == '\r' || line[len - 1] == '\n')) {
        line[--len] = '\0';
    }
}

static int read_until_final(
    libusb_device_handle *handle,
    unsigned char endpoint_in,
    const char *echo,
    int timeout_ms,
    char **response,
    char *error,
    size_t error_len
) {
    long long deadline = now_ms() + timeout_ms;
    char partial[1024];
    size_t partial_len = 0;
    char *out = NULL;
    size_t out_len = 0;
    size_t out_capacity = 0;

    while (now_ms() < deadline) {
        unsigned char buffer[512];
        int transferred = 0;
        int remaining = (int)(deadline - now_ms());
        if (remaining < 1) break;
        int step_timeout = remaining < 250 ? remaining : 250;
        int rc = libusb_bulk_transfer(handle, endpoint_in, buffer, sizeof(buffer), &transferred, step_timeout);
        if (rc == LIBUSB_ERROR_TIMEOUT) continue;
        if (rc != 0) {
            free(out);
            set_libusb_error(error, error_len, "USB bulk read failed", rc);
            return rc;
        }
        if (transferred <= 0) continue;

        for (int i = 0; i < transferred; i++) {
            char c = (char)buffer[i];
            if (c == '\r' || c == '\n') {
                partial[partial_len] = '\0';
                trim_line(partial);
                if (partial[0] != '\0' && (!echo || strcmp(partial, echo) != 0)) {
                    if (strcmp(partial, "OK") == 0) {
                        if (!out) out = strdup("");
                        *response = out;
                        return 0;
                    }
                    if (strcmp(partial, "ERROR") == 0 || strncmp(partial, "+CME ERROR:", 11) == 0 || strncmp(partial, "+CMS ERROR:", 11) == 0) {
                        set_error(error, error_len, partial);
                        free(out);
                        return -2;
                    }
                    if (append_text(&out, &out_len, &out_capacity, partial) != 0) {
                        free(out);
                        set_error(error, error_len, "out of memory");
                        return -3;
                    }
                }
                partial_len = 0;
            } else if (partial_len + 1 < sizeof(partial)) {
                partial[partial_len++] = c;
            }
        }
    }

    partial[partial_len] = '\0';
    trim_line(partial);
    if (partial[0] != '\0' && (!echo || strcmp(partial, echo) != 0)) {
        if (strcmp(partial, "OK") == 0) {
            if (!out) out = strdup("");
            *response = out;
            return 0;
        }
        if (strcmp(partial, "ERROR") == 0 || strncmp(partial, "+CME ERROR:", 11) == 0 || strncmp(partial, "+CMS ERROR:", 11) == 0) {
            set_error(error, error_len, partial);
            free(out);
            return -2;
        }
    }

    free(out);
    set_error(error, error_len, "AT command timeout");
    return LIBUSB_ERROR_TIMEOUT;
}

static int wait_for_prompt(libusb_device_handle *handle, unsigned char endpoint_in, int timeout_ms, char *error, size_t error_len) {
    long long deadline = now_ms() + timeout_ms;
    while (now_ms() < deadline) {
        unsigned char buffer[256];
        int transferred = 0;
        int remaining = (int)(deadline - now_ms());
        if (remaining < 1) break;
        int rc = libusb_bulk_transfer(handle, endpoint_in, buffer, sizeof(buffer), &transferred, remaining < 250 ? remaining : 250);
        if (rc == LIBUSB_ERROR_TIMEOUT) continue;
        if (rc != 0) {
            set_libusb_error(error, error_len, "USB prompt read failed", rc);
            return rc;
        }
        for (int i = 0; i < transferred; i++) {
            if (buffer[i] == '>') return 0;
        }
    }
    set_error(error, error_len, "AT prompt timeout");
    return LIBUSB_ERROR_TIMEOUT;
}

static int write_all(libusb_device_handle *handle, unsigned char endpoint_out, const char *bytes, int length, int timeout_ms, char *error, size_t error_len) {
    int offset = 0;
    while (offset < length) {
        int transferred = 0;
        int rc = libusb_bulk_transfer(handle, endpoint_out, (unsigned char *)bytes + offset, length - offset, &transferred, timeout_ms);
        if (rc != 0) {
            set_libusb_error(error, error_len, "USB bulk write failed", rc);
            return rc;
        }
        if (transferred <= 0) {
            set_error(error, error_len, "USB bulk write made no progress");
            return -4;
        }
        offset += transferred;
    }
    return 0;
}

static int transact_on_endpoints(
    libusb_device_handle *handle,
    unsigned char endpoint_out,
    unsigned char endpoint_in,
    const char *command,
    const char *prompt_payload,
    int timeout_ms,
    char **response,
    char *error,
    size_t error_len
) {
    drain_endpoint(handle, endpoint_in);

    char command_line[512];
    snprintf(command_line, sizeof(command_line), "%s\r", command);
    int rc = write_all(handle, endpoint_out, command_line, (int)strlen(command_line), timeout_ms, error, error_len);
    if (rc != 0) return rc;

    if (prompt_payload) {
        rc = wait_for_prompt(handle, endpoint_in, timeout_ms < 5000 ? timeout_ms : 5000, error, error_len);
        if (rc != 0) return rc;
        rc = write_all(handle, endpoint_out, prompt_payload, (int)strlen(prompt_payload), timeout_ms, error, error_len);
        if (rc != 0) return rc;
        return read_until_final(handle, endpoint_in, NULL, timeout_ms, response, error, error_len);
    }

    return read_until_final(handle, endpoint_in, command, timeout_ms, response, error, error_len);
}

static int find_working_interface(libusb_device *device, libusb_device_handle *handle, struct ec25_usb_session *session) {
    struct libusb_config_descriptor *config = NULL;
    int rc = libusb_get_active_config_descriptor(device, &config);
    if (rc != 0) return rc;

    int result = LIBUSB_ERROR_NOT_FOUND;
    for (int i = 0; i < config->bNumInterfaces && result != 0; i++) {
        const struct libusb_interface *iface = &config->interface[i];
        for (int a = 0; a < iface->num_altsetting && result != 0; a++) {
            const struct libusb_interface_descriptor *alt = &iface->altsetting[a];
            unsigned char ep_in = 0;
            unsigned char ep_out = 0;
            for (int e = 0; e < alt->bNumEndpoints; e++) {
                const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
                if (!endpoint_bulk(ep)) continue;
                if (endpoint_in(ep)) ep_in = ep->bEndpointAddress;
                if (endpoint_out(ep)) ep_out = ep->bEndpointAddress;
            }
            if (!ep_in || !ep_out) continue;

            rc = libusb_claim_interface(handle, alt->bInterfaceNumber);
            if (rc != 0) continue;

            char *response = NULL;
            char error[128] = {0};
            rc = transact_on_endpoints(handle, ep_out, ep_in, "AT", NULL, 3000, &response, error, sizeof(error));
            int ok = rc == 0;
            if (!ok) {
                libusb_release_interface(handle, alt->bInterfaceNumber);
            } else {
                session->interface_number = alt->bInterfaceNumber;
                session->endpoint_in = ep_in;
                session->endpoint_out = ep_out;
                snprintf(session->description, sizeof(session->description), "USB 2c7c:0125 if%d out=0x%02x in=0x%02x", alt->bInterfaceNumber, ep_out, ep_in);
                result = 0;
            }
            free(response);
        }
    }

    libusb_free_config_descriptor(config);
    return result;
}

int ec25_usb_open(uint16_t vid, uint16_t pid, ec25_usb_session **session, char *error, size_t error_len) {
    if (!session) {
        set_error(error, error_len, "session pointer is null");
        return -1;
    }
    *session = NULL;

    libusb_context *context = NULL;
    int rc = libusb_init(&context);
    if (rc != 0) {
        set_libusb_error(error, error_len, "libusb init failed", rc);
        return rc;
    }

    libusb_device **devices = NULL;
    ssize_t count = libusb_get_device_list(context, &devices);
    if (count < 0) {
        set_libusb_error(error, error_len, "USB device list failed", (int)count);
        libusb_exit(context);
        return (int)count;
    }

    int found = 0;
    int last_rc = LIBUSB_ERROR_NOT_FOUND;
    for (ssize_t i = 0; i < count; i++) {
        struct libusb_device_descriptor desc;
        rc = libusb_get_device_descriptor(devices[i], &desc);
        if (rc != 0 || desc.idVendor != vid || desc.idProduct != pid) continue;
        found = 1;

        libusb_device_handle *handle = NULL;
        rc = libusb_open(devices[i], &handle);
        if (rc != 0) {
            last_rc = rc;
            continue;
        }

        struct ec25_usb_session *candidate = calloc(1, sizeof(struct ec25_usb_session));
        if (!candidate) {
            libusb_close(handle);
            libusb_free_device_list(devices, 1);
            libusb_exit(context);
            set_error(error, error_len, "out of memory");
            return -3;
        }
        candidate->context = context;
        candidate->handle = handle;
        candidate->interface_number = -1;

        rc = find_working_interface(devices[i], handle, candidate);
        if (rc == 0) {
            *session = candidate;
            libusb_free_device_list(devices, 1);
            return 0;
        }

        last_rc = rc;
        libusb_close(handle);
        free(candidate);
    }

    libusb_free_device_list(devices, 1);
    libusb_exit(context);
    if (!found) {
        set_error(error, error_len, "未找到 2c7c:0125 USB 设备");
        return LIBUSB_ERROR_NOT_FOUND;
    }
    set_libusb_error(error, error_len, "未找到可响应 AT 的 USB bulk 接口", last_rc);
    return last_rc;
}

int ec25_usb_send(ec25_usb_session *session, const char *command, const char *prompt_payload, int timeout_ms, char **response, char *error, size_t error_len) {
    if (!session || !session->handle || !command || !response) {
        set_error(error, error_len, "invalid USB AT session");
        return -1;
    }
    *response = NULL;
    return transact_on_endpoints(
        session->handle,
        session->endpoint_out,
        session->endpoint_in,
        command,
        prompt_payload,
        timeout_ms,
        response,
        error,
        error_len
    );
}

void ec25_usb_close(ec25_usb_session *session) {
    if (!session) return;
    if (session->handle) {
        if (session->interface_number >= 0) {
            libusb_release_interface(session->handle, session->interface_number);
        }
        libusb_close(session->handle);
    }
    if (session->context) {
        libusb_exit(session->context);
    }
    free(session);
}

void ec25_usb_free(char *pointer) {
    free(pointer);
}

const char *ec25_usb_description(ec25_usb_session *session) {
    if (!session) return "";
    return session->description;
}
