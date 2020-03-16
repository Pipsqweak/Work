SELECT
      s.Name as [ServerName]
    , p.Path as [Path]
    , i.Name as [Identity]
    , r.[Right] as [Right]
FROM
    Rights r INNER JOIN Paths p ON r.PathID = p.ID
             INNER JOIN Identities i ON r.IdentityID = i.ID
             INNER JOIN Servers s ON p.ServerID = s.ID
