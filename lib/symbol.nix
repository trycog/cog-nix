# SCIP symbol string builder
# Format: "file . {package} unversioned {descriptor}"
let
  simpleIdentRe = "[a-zA-Z0-9_+$-]+";

  escapeIdent = name:
    if builtins.match simpleIdentRe name != null
    then name
    else "`${builtins.replaceStrings ["\`"] ["\`\`"] name}`";
in
{
  variableSymbol = packageName: name:
    "file . ${escapeIdent packageName} unversioned ${escapeIdent name}.";

  fieldSymbol = packageName: owner: name:
    "file . ${escapeIdent packageName} unversioned ${escapeIdent owner}#${escapeIdent name}.";

  functionSymbol = packageName: name:
    "file . ${escapeIdent packageName} unversioned ${escapeIdent name}().";

  moduleSymbol = packageName: name:
    "file . ${escapeIdent packageName} unversioned ${escapeIdent name}#";

  localSymbol = index:
    "local ${toString index}";

  inherit escapeIdent;
}
