#ifndef CEC25USB_H
#define CEC25USB_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ec25_usb_session ec25_usb_session;

int ec25_usb_open(uint16_t vid, uint16_t pid, ec25_usb_session **session, char *error, size_t error_len);
int ec25_usb_send(ec25_usb_session *session, const char *command, const char *prompt_payload, int timeout_ms, char **response, char *error, size_t error_len);
void ec25_usb_close(ec25_usb_session *session);
void ec25_usb_free(char *pointer);
const char *ec25_usb_description(ec25_usb_session *session);

#ifdef __cplusplus
}
#endif

#endif
