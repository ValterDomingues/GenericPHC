/*
  Open u_reccli rows (fechada=0) for the current user, limited to the last
  2 business days (Monday-Friday). Holidays are not excluded.

  Window (inclusive), DATEFIRST-independent (0=Mon .. 6=Sun):
    Mon     -> Friday  .. Monday
    Tue-Fri -> yesterday .. today
    Sat     -> Thursday .. Friday
    Sun     -> Thursday .. Friday

  PHC slot: replace <<mUsr>> as today.
*/

DECLARE @mUser VARCHAR(30) = '<<mUsr>>'
DECLARE @mToday DATE = CONVERT(DATE, GETDATE())
DECLARE @mDow INT = DATEDIFF(DAY, 0, @mToday) % 7
DECLARE @mFrom DATE =
	CASE @mDow
		WHEN 0 THEN DATEADD(DAY, -3, @mToday) -- Mon: start Friday
		WHEN 5 THEN DATEADD(DAY, -2, @mToday) -- Sat: start Thursday
		WHEN 6 THEN DATEADD(DAY, -3, @mToday) -- Sun: start Thursday
		ELSE DATEADD(DAY, -1, @mToday)        -- Tue-Fri: start yesterday
	END
DECLARE @mTo DATE =
	CASE @mDow
		WHEN 5 THEN DATEADD(DAY, -1, @mToday) -- Sat: end Friday
		WHEN 6 THEN DATEADD(DAY, -2, @mToday) -- Sun: end Friday
		ELSE @mToday
	END

SELECT mInc.u_recclistamp,mInc.norec,mInc.tprec,mInc.data,mInc.entrada,mInc.nome,
	mInc.moraobra,mInc.cpostobra,mInc.descri,mInc.responscli,mInc.contactocli,
	mInc.utilizador,us.vendnm,mInc.responsavel
FROM us (NOLOCK) INNER JOIN u_atend (NOLOCK) ON us.iniciais=u_atend.iniciais
	INNER JOIN (SELECT u_recclistamp,norec,tprec,CONVERT(DATE,data) data,entrada,
			u_reccli.nome,moraobra,cpostobra,descri,responscli,contactocli,
			utilizador,cl.vendedor,ISNULL(u_tprecresp.responsavel,'') responsavel
		FROM u_reccli (NOLOCK) INNER JOIN cl (NOLOCK) ON u_reccli.no=cl.no AND u_reccli.estab=cl.estab
			INNER JOIN u_tprec (NOLOCK) ON u_reccli.numtpre=u_tprec.numtpre
			LEFT JOIN u_tprecresp (NOLOCK) ON u_tprec.u_tprecstamp=u_tprecresp.u_tprecstamp
		WHERE u_reccli.fechada=0
			AND CONVERT(DATE, u_reccli.data) >= @mFrom
			AND CONVERT(DATE, u_reccli.data) <= @mTo) mInc ON us.usercode=mInc.utilizador OR us.vendedor=mInc.vendedor
			OR u_atend.design=mInc.responsavel
WHERE us.inactivo=0 AND u_atend.inactivo=0  AND us.iniciais=@mUser
