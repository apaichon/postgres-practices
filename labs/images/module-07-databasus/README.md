# Databasus student-manual screenshots

> Account and database names in this text use `xx` as an anonymized placeholder. Raw screenshots and verification records are historical evidence; use your assigned account for new runs.

These PNGs accompany the [student manual](../../module-07-databasus-student-manual.md).
They are captures of the running classroom application, made on **2026-11-08**
with **Playwright 1.55.1 / Chromium 140.0.7339.186**, at a desktop viewport of
1440 × 1000 and device scale factor 1. The browser timezone was Europe/Berlin.
The application footer reported **Databasus 3.60.0**.

Screenshots use the existing **Student xx** account/workspace and source. They
show real UI states, including a backup and restore actually performed through
the browser. They are not mock application screens. The final restore-form and
restore-history PNGs capture the modal element directly with Playwright so the
target settings and success status are readable. Passwords remain masked;
sign-in was captured with empty inputs. No browser authentication state,
password files, database archives or private API responses belong in this folder.

| Image | State |
| --- | --- |
| `01-sign-in.png` | Empty sign-in form |
| `02-workspace.png` | Student workspace and existing backup history |
| `03-source-configuration.png` | Assigned database and schema scope |
| `04-connection-test.png` | Successful source connection test |
| `05-backup-completed.png` | Newly created successful backup |
| `06-restore-action.png` | Restore icon and tooltip on that backup |
| `07-restore-target-options.png` | Initial target form, including its source-name default |
| `09-restore-ready.png` | Tested recovery target and correct advanced options |
| `10-restore-completed.png` | Restore history with Successful status |
| `11-backup-settings.png` | Storage, encryption and retention editor |
| `12-schedule-preview.png` | Unsaved schedule preview; canceled afterward |
| `13-download-action.png` | Download icon and tooltip |

The numbering follows the capture sequence; only the 12 images used in the
manual are retained. The UI shows a completed job as **Successful**, while the
API and course helper report **COMPLETED**. API timestamps are UTC; the browser
screenshots display local time.

## Verified recovery

[verification.json](verification.json) records the non-secret job IDs and checks
for the illustrated run. The practice seed, damage and target preparation used
the actual Student xx SSH helper. The backup and restore were initiated in the
web UI. Subsequent API reads confirmed both job statuses as `COMPLETED`, and
direct SQL queries confirmed:

- `claimsure_xx`, user `student_xx`, port `5432`: practice IDs **1,3**.
- `claimsure_databasus_xx`, same user/port: practice IDs **1,2**.
- All **14** insurance-table counts matched the baseline captured before backup.

The capture leaves those practice states available for inspection. The schedule
preview was canceled, and the assigned source configuration was preserved.
Download was illustrated by its UI action/tooltip; a backup archive is not
distributed with the manual. The desktop SQL-client section contains executable
SQL and expected results; it does not claim to show a DBeaver/pgAdmin capture.

## Updating the images

Use a provisioned demonstration student and the same ordered workflow as the
manual. Read credentials privately from the existing deployment, sign in with
Playwright, and wait for the relevant UI state before capturing. Record the new
backup UUID before damage, prepare only its dedicated target, and wait for the
restore's own success before capturing its history. Verify both databases and
baseline counts again. Inspect each image for readable settings and hidden
passwords before replacing the current assets.

Regenerate the printable PDF from the manual after changing text or images.
Keep all image paths relative so the Markdown manual can be moved with this
image directory.
