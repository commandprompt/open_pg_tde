#ifndef OPEN_PG_TDE_EVENT_CAPTURE_H
#define OPEN_PG_TDE_EVENT_CAPTURE_H

typedef enum
{
	TDE_ENCRYPT_MODE_RETAIN = 0,
	TDE_ENCRYPT_MODE_ENCRYPT,
	TDE_ENCRYPT_MODE_PLAIN,
} TDEEncryptMode;

extern void TdeEventCaptureInit(void);
extern TDEEncryptMode currentTdeEncryptModeValidated(void);

#endif
