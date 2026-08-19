# Dialyzer ignore list — TERM format (a list), NOT the legacy plain-text
# `.dialyzer_ignore` file. `mix dialyzer.json` reads ONLY this `.exs` shape;
# a plain-text file is silently ignored (no error, nothing suppressed).
#
# Entries are tuples or regexes matched against the warning, e.g.:
#   {~r/Unknown type: Some.Module.t\/0/}
[]
