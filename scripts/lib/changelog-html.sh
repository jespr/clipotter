#!/bin/bash
# Generates website/changelog.html from CHANGELOG.md.
# Sourced by scripts/release.sh; also runnable standalone:
#
#   bash scripts/lib/changelog-html.sh

_changelog_html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# Emits tab-delimited records: <date>\t<version>\t<bullets joined by §§§>
# Skips [Unreleased] and any version header without a date.
_changelog_emit_versions() {
  local file="$1"
  local version="" date="" bullets=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^##\ \[([^\]]+)\]\ -\ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      if [ -n "$version" ] && [ -n "$date" ]; then
        printf '%s\t%s\t%s\n' "$date" "$version" "$bullets"
      fi
      version="${BASH_REMATCH[1]}"
      date="${BASH_REMATCH[2]}"
      bullets=""
    elif [[ "$line" =~ ^##\  ]]; then
      if [ -n "$version" ] && [ -n "$date" ]; then
        printf '%s\t%s\t%s\n' "$date" "$version" "$bullets"
      fi
      version=""; date=""; bullets=""
    elif [[ "$line" =~ ^-\ (.+)$ ]]; then
      if [ -n "$version" ]; then
        if [ -z "$bullets" ]; then bullets="${BASH_REMATCH[1]}"; else bullets="${bullets}§§§${BASH_REMATCH[1]}"; fi
      fi
    fi
  done < "$file"
  if [ -n "$version" ] && [ -n "$date" ]; then
    printf '%s\t%s\t%s\n' "$date" "$version" "$bullets"
  fi
}

generate_changelog_html() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local out="$root/website/changelog.html"
  local tmp
  tmp="$(mktemp)"

  _changelog_emit_versions "$root/CHANGELOG.md" > "$tmp"
  sort -r -o "$tmp" "$tmp"   # ISO dates sort lexicographically; newest first

  local cards=""
  while IFS=$'\t' read -r date version bullets; do
    [ -n "$version" ] || continue
    local items="" item
    while IFS= read -r item || [ -n "$item" ]; do
      [ -n "$item" ] || continue
      item="$(_changelog_html_escape "$item")"
      items+="                    <li class=\"relative pl-5 before:content-[''] before:absolute before:left-1 before:top-[0.55rem] before:size-1 before:rounded-full before:bg-zinc-600\">$item</li>"$'\n'
    done < <(printf '%s' "$bullets" | sed 's/§§§/\'$'\n''/g')
    [ -n "$items" ] || continue

    cards+="                <article id=\"v$version\" class=\"rounded-xl outline-1 -outline-offset-1 outline-white/10 bg-white/[0.02] p-6 md:p-8\">
                    <header class=\"flex flex-wrap items-center gap-3 mb-4\">
                        <h2 class=\"text-lg font-medium text-white font-mono tracking-tight\">v$version</h2>
                        <span class=\"ml-auto text-sm text-zinc-500 font-mono\">$date</span>
                    </header>
                    <ul class=\"space-y-2 text-sm text-zinc-400 list-none pl-0\">
$items                    </ul>
                </article>
"
  done < "$tmp"
  rm -f "$tmp"

  cat > "$out" <<HTML
<!DOCTYPE html>
<html lang="en" style="color-scheme: dark">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Changelog — Transcript</title>
    <meta name="description" content="Release notes for Transcript — local, on-device video & audio transcription for Mac.">
    <link rel="icon" type="image/png" sizes="96x96" href="/transcript/favicon-96.png">
    <link rel="icon" type="image/png" sizes="32x32" href="/transcript/favicon-32.png">
    <link rel="apple-touch-icon" sizes="180x180" href="/transcript/apple-touch-icon.png">
    <script src="https://cdn.tailwindcss.com"></script>
    <style>html { scroll-behavior: smooth; }</style>
</head>
<body class="bg-[#0a0a0a] text-zinc-300 antialiased">
    <nav class="relative z-20">
        <div class="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between text-sm">
            <a href="/transcript/" class="flex items-center gap-2 text-white font-medium hover:opacity-80 transition-opacity"><img src="/transcript/icon.png" alt="" class="size-6 rounded-[28%]">Transcript</a>
            <div class="flex items-center gap-5 text-zinc-400">
                <a href="/transcript/changelog.html" class="text-white" aria-current="page">Changelog</a>
                <a href="https://github.com/jespr/transcript" class="hover:text-white transition-colors">GitHub</a>
            </div>
        </div>
    </nav>
    <main class="relative z-10">
        <section class="pt-10 pb-8 md:pt-16 md:pb-12">
            <div class="max-w-3xl mx-auto px-6">
                <h1 class="text-3xl sm:text-4xl font-medium tracking-tight text-white">Changelog</h1>
                <p class="mt-3 text-zinc-400 max-w-[60ch]">Everything that's shipped in Transcript, newest first.</p>
            </div>
        </section>
        <section class="pb-24">
            <div class="max-w-3xl mx-auto px-6 space-y-4">
$cards            </div>
        </section>
    </main>
</body>
</html>
HTML
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  generate_changelog_html
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "✅ Wrote $root/website/changelog.html"
fi
