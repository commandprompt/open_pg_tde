/*-------------------------------------------------------------------------
 *
 * open_pg_tde_tempfile.h
 *	  Temporary (query-spill) file encryption for open_pg_tde.
 *
 *-------------------------------------------------------------------------
 */
#ifndef OPEN_PG_TDE_TEMPFILE_H
#define OPEN_PG_TDE_TEMPFILE_H

#ifdef USE_TDE_HOOKS

/* Install the temporary-file encryption hooks. Call from _PG_init. */
extern void TdeTempFileInit(void);

#endif							/* USE_TDE_HOOKS */

#endif							/* OPEN_PG_TDE_TEMPFILE_H */
