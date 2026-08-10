*==============================================================================
* send_periodic_email.prg
*------------------------------------------------------------------------------
* Uses SqlToArray() to fetch MS SQL Server rows into a VFP array, then builds
* a bullet-list email body and sends it via CDO (Windows).
*
* Schedule with Windows Task Scheduler (recommended) or call from a timer.
*
* Prerequisites:
*   - sql_to_array.prg available (SET PROCEDURE TO sql_to_array ADDITIVE)
*   - Working SQL Server ODBC / SQL Server driver
*   - SMTP reachable from the machine (configure below)
*==============================================================================

LOCAL laRows[1], lnRows, lcErr, lcBody, lnI, lnCols, lcLine, lnCol

SET PROCEDURE TO sql_to_array ADDITIVE

*------------------------------------------------------------------------------
* SMTP / message settings — edit for your environment
*------------------------------------------------------------------------------
LOCAL lcSmtpServer, lnSmtpPort, lcFrom, lcTo, lcSubject
LOCAL lcSmtpUser, lcSmtpPassword, llUseAuth

lcSmtpServer   = "smtp.example.com"
lnSmtpPort     = 587
lcFrom         = "noreply@example.com"
lcTo           = "recipient@example.com"
lcSubject      = "Periodic database report"
lcSmtpUser     = ""      && set if SMTP requires login
lcSmtpPassword = ""
llUseAuth      = .F.     && .T. when lcSmtpUser/password are set

*------------------------------------------------------------------------------
* 1) Query SQL Server → VFP array
*    Edit the SQL inside sql_to_array.prg (marked INSERT YOUR SQL QUERY HERE).
*------------------------------------------------------------------------------
lnRows = SqlToArray(@laRows, @lcErr)
IF lnRows < 0
    = LogAndAlert("Database query failed: " + lcErr)
    RETURN .F.
ENDIF

*------------------------------------------------------------------------------
* 2) Format array rows as a plain-text bullet list for the email body
*------------------------------------------------------------------------------
lcBody = "Periodic database report" + CHR(13) + CHR(10) + ;
         "Rows returned: " + TRANSFORM(lnRows) + CHR(13) + CHR(10) + ;
         CHR(13) + CHR(10)

IF lnRows = 0
    lcBody = lcBody + "No results found."
ELSE
    lnCols = ALEN(laRows, 2)
    IF lnCols = 0
        * 1D array fallback
        FOR lnI = 1 TO lnRows
            lcBody = lcBody + "- " + ALLTRIM(TRANSFORM(laRows[lnI])) + CHR(13) + CHR(10)
        ENDFOR
    ELSE
        FOR lnI = 1 TO lnRows
            lcLine = ""
            FOR lnCol = 1 TO lnCols
                IF lnCol > 1
                    lcLine = lcLine + " | "
                ENDIF
                lcLine = lcLine + ALLTRIM(TRANSFORM(laRows[lnI, lnCol]))
            ENDFOR
            lcBody = lcBody + "- " + lcLine + CHR(13) + CHR(10)
        ENDFOR
    ENDIF
ENDIF

*------------------------------------------------------------------------------
* 3) Send email
*------------------------------------------------------------------------------
IF NOT SendMailCdo(lcSmtpServer, lnSmtpPort, lcFrom, lcTo, lcSubject, lcBody, ;
                   llUseAuth, lcSmtpUser, lcSmtpPassword)
    RETURN .F.
ENDIF

RETURN .T.


FUNCTION SendMailCdo
LPARAMETERS tcServer, tnPort, tcFrom, tcTo, tcSubject, tcBody, ;
            tlUseAuth, tcUser, tcPassword

LOCAL loMsg, loConf, lcSchema, loEx

lcSchema = "http://schemas.microsoft.com/cdo/configuration/"

TRY
    loMsg  = CREATEOBJECT("CDO.Message")
    loConf = CREATEOBJECT("CDO.Configuration")

    WITH loConf.Fields
        .Item(lcSchema + "sendusing") = 2                && cdoSendUsingPort
        .Item(lcSchema + "smtpserver") = tcServer
        .Item(lcSchema + "smtpserverport") = tnPort
        .Item(lcSchema + "smtpconnectiontimeout") = 30
        * 2 = cdoTLS (STARTTLS). Use 1 for SSL on port 465 if required.
        .Item(lcSchema + "smtpusessl") = .F.
        IF tlUseAuth
            .Item(lcSchema + "smtpauthenticate") = 1     && cdoBasic
            .Item(lcSchema + "sendusername") = tcUser
            .Item(lcSchema + "sendpassword") = tcPassword
        ENDIF
        .Update()
    ENDWITH

    loMsg.Configuration = loConf
    loMsg.From = tcFrom
    loMsg.To = tcTo
    loMsg.Subject = tcSubject
    loMsg.TextBody = tcBody
    loMsg.Send()
    RETURN .T.

CATCH TO loEx
    = LogAndAlert("Email send failed: " + loEx.Message)
    RETURN .F.
ENDTRY
ENDFUNC


FUNCTION LogAndAlert
LPARAMETERS tcMessage
* Replace with your app logging if needed
? tcMessage
* MESSAGEBOX(tcMessage, 16, "Periodic email")
RETURN .T.
ENDFUNC
