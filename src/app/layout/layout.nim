import tiara/components

proc layout*(content: string): string =
  let tiaraStyles = $Tiara.defaultStyles()

  return """
<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>nimchat | Crown + Tiara</title>
""" & tiaraStyles & """
  <link rel="stylesheet" href="/app.css">
</head>
<body>
  <main class="app-frame">
""" & content & """
  </main>
</body>
</html>
"""
