# Analyzer: tokenizes Nix source and produces SCIP document data
# Takes: { source, relativePath, filename, packageName }
# Returns: { relativePath, language, occurrences, symbols }

{ source, relativePath, filename, packageName }:
let
  sym = import ./symbol.nix;

  # --- Constants ---
  ROLE_DEFINITION = 1;
  ROLE_IMPORT = 2;
  ROLE_WRITE = 4;
  ROLE_READ = 8;

  KIND_CONSTANT = 8;
  KIND_FIELD = 15;
  KIND_FUNCTION = 17;
  KIND_MODULE = 29;
  KIND_PARAMETER = 37;
  KIND_VARIABLE = 61;

  keywords = {
    "let" = true; "in" = true; "rec" = true; "with" = true;
    "inherit" = true; "if" = true; "then" = true; "else" = true;
    "assert" = true; "or" = true; "true" = true; "false" = true;
    "null" = true; "import" = true;
  };

  isKeyword = name: builtins.hasAttr name keywords;
  isFlake = builtins.match ".*flake[.]nix" filename != null;

  flakeOutputModules = {
    "packages" = true; "devShells" = true; "nixosConfigurations" = true;
    "darwinConfigurations" = true; "homeConfigurations" = true;
    "overlays" = true; "lib" = true; "nixosModules" = true;
    "darwinModules" = true; "homeModules" = true; "checks" = true;
    "apps" = true; "formatter" = true; "templates" = true;
  };

  # --- Tokenizer ---
  # Uses builtins.split with a regex to extract tokens, then walks the
  # result list tracking line/col positions.

  tokenPattern = builtins.concatStringsSep "|" [
    "([a-zA-Z_][a-zA-Z0-9_-]*)"         # 1: identifier/keyword
    "([0-9]+)"                            # 2: integer
    "(\")"                                # 3: double quote
    "('')"                                # 4: multiline string delim
    "(#.*)"                               # 5: line comment (rest of line)
    "([.][.][.])"                         # 6: ellipsis
    "(\\$\\{)"                            # 7: interpolation start ${
    "(==|!=|<=|>=|->|[+][+]|//)"         # 8: two-char operators
    "([=:;.,@?{}()+*/<>!-]|\\[|\\])"    # 9: single-char tokens
  ];

  # Find which group in a match list is non-null, return { group, value }
  findMatch = groups:
    let
      indexed = builtins.genList (i: { idx = i + 1; val = builtins.elemAt groups i; }) (builtins.length groups);
      matched = builtins.filter (x: x.val != null) indexed;
    in
    if matched == [] then null
    else builtins.head matched;

  # Count newlines in a string
  countNewlinesInStr = str:
    let parts = builtins.split "\n" str;
    in builtins.length (builtins.filter builtins.isList parts);

  # Get length of text after final newline
  lastLineCol = str:
    let
      parts = builtins.filter builtins.isString (builtins.split "\n" str);
      n = builtins.length parts;
    in
    if n == 0 then 0
    else builtins.stringLength (builtins.elemAt parts (n - 1));

  # Advance line/col through a string
  advancePos = str: line: col:
    let nls = countNewlinesInStr str;
    in
    if nls == 0 then { inherit line; col = col + builtins.stringLength str; }
    else { line = line + nls; col = lastLineCol str; };

  # Tokenize source into list of { group, value, line, col, endCol }
  tokenize = src:
    let
      parts = builtins.split tokenPattern src;

      walk = items: line: col: state: acc:
        if items == [] then acc
        else
          let
            first = builtins.head items;
            rest = builtins.tail items;
          in
          if builtins.isString first then
            let pos = advancePos first line col;
            in walk rest pos.line pos.col state acc
          else
            let
              m = findMatch first;
              tokenLen = builtins.stringLength m.val;
              token = { group = m.idx; value = m.val; inherit line col; endCol = col + tokenLen; };
              newPos = advancePos m.val line col;
            in
            if state == "normal" then
              if m.idx == 3 then
                walk rest newPos.line newPos.col "dquote" acc
              else if m.idx == 4 then
                walk rest newPos.line newPos.col "mquote" acc
              else if m.idx == 5 then
                walk rest newPos.line newPos.col state acc
              else
                walk rest newPos.line newPos.col state (acc ++ [token])
            else if state == "dquote" then
              if m.idx == 3 then
                walk rest newPos.line newPos.col "normal" acc
              else
                walk rest newPos.line newPos.col state acc
            else if state == "mquote" then
              if m.idx == 4 then
                walk rest newPos.line newPos.col "normal" acc
              else
                walk rest newPos.line newPos.col state acc
            else
              walk rest newPos.line newPos.col state acc;
    in
    walk parts 0 0 "normal" [];

  tokens = tokenize source;
  tokenCount = builtins.length tokens;

  tokenAt = i:
    if i >= 0 && i < tokenCount
    then builtins.elemAt tokens i
    else { group = 0; value = ""; line = 0; col = 0; endCol = 0; };

  # --- Lookahead helpers ---

  # Check if { at index i is a pattern (ends with }:)
  isPatternBrace = i:
    let
      findClose = j: depth:
        if j >= tokenCount then null
        else
          let t = tokenAt j;
          in
          if t.value == "{" then findClose (j + 1) (depth + 1)
          else if t.value == "}" then
            if depth == 0 then j
            else findClose (j + 1) (depth - 1)
          else findClose (j + 1) depth;
      closeIdx = findClose (i + 1) 0;
    in
    if closeIdx == null then false
    else (tokenAt (closeIdx + 1)).value == ":";

  # Collect pattern parameter idents between { and }
  collectPatternIdents = from: to: depth:
    if from >= to then []
    else
      let t = tokenAt from;
      in
      if t.value == "{" then collectPatternIdents (from + 1) to (depth + 1)
      else if t.value == "}" then collectPatternIdents (from + 1) to (depth - 1)
      else if depth == 0 && t.group == 1 && !(isKeyword t.value) then
        [{ idx = from; tok = t; }] ++ collectPatternIdents (from + 1) to depth
      else
        collectPatternIdents (from + 1) to depth;

  findMatchingClose = i:
    let
      go = j: depth:
        if j >= tokenCount then tokenCount
        else
          let t = tokenAt j;
          in
          if t.value == "{" then go (j + 1) (depth + 1)
          else if t.value == "}" then
            if depth == 0 then j
            else go (j + 1) (depth - 1)
          else go (j + 1) depth;
    in go (i + 1) 0;

  # --- Emit helpers ---
  emitDef = state: tok: defSym: kind:
    let
      occ = {
        range = [tok.line tok.col tok.endCol];
        symbol = defSym;
        symbolRoles = ROLE_DEFINITION + ROLE_WRITE;
      };
      symInfo = {
        symbol = defSym;
        inherit kind;
        displayName = tok.value;
      };
    in state // {
      occurrences = state.occurrences ++ [occ];
      symbols = state.symbols ++ [symInfo];
      defs = state.defs // { ${tok.value} = defSym; };
    };

  emitRef = state: tok: refSym: roles:
    state // {
      occurrences = state.occurrences ++ [{
        range = [tok.line tok.col tok.endCol];
        symbol = refSym;
        symbolRoles = roles;
      }];
    };

  # --- Analysis pass ---
  initialState = {
    occurrences = [];
    symbols = [];
    defs = {};
    localCounter = 0;
    skipUntil = -1;
    inInherit = false;       # true after seeing "inherit" until ";"
    inheritParenDepth = 0;   # tracks parens in inherit (expr) ...
  };

  analyze = builtins.foldl' (state: item:
    let
      i = item.idx;
      tok = item.tok;
      prev = tokenAt (i - 1);
      next = tokenAt (i + 1);
      next2 = tokenAt (i + 2);
    in
    if i < state.skipUntil then state
    else

    # --- Semicolon: reset inherit state ---
    if tok.value == ";" then
      state // { inInherit = false; inheritParenDepth = 0; }

    # --- Track parens inside inherit (expr) ---
    else if state.inInherit && tok.value == "(" then
      state // { inheritParenDepth = state.inheritParenDepth + 1; }
    else if state.inInherit && tok.value == ")" then
      state // { inheritParenDepth = state.inheritParenDepth - 1; }

    # --- Pattern parameters: { a, b, ... }: ---
    else if tok.value == "{" && tok.group == 9 && isPatternBrace i then
      let
        closeIdx = findMatchingClose i;
        idents = collectPatternIdents (i + 1) closeIdx 0;
        processIdent = s: ident:
          let
            paramSym = sym.localSymbol s.localCounter;
            occ = {
              range = [ident.tok.line ident.tok.col ident.tok.endCol];
              symbol = paramSym;
              symbolRoles = ROLE_DEFINITION + ROLE_WRITE;
            };
            symInfo = {
              symbol = paramSym;
              kind = KIND_PARAMETER;
              displayName = ident.tok.value;
            };
          in s // {
            occurrences = s.occurrences ++ [occ];
            symbols = s.symbols ++ [symInfo];
            defs = s.defs // { ${ident.tok.value} = paramSym; };
            localCounter = s.localCounter + 1;
          };
        newState = builtins.foldl' processIdent state idents;
      in newState // { skipUntil = closeIdx + 1; }

    # --- "inherit" keyword: enter inherit mode ---
    else if tok.group == 1 && tok.value == "inherit" then
      state // { inInherit = true; inheritParenDepth = 0; }

    # --- Identifier tokens ---
    else if tok.group == 1 && !(isKeyword tok.value) then

      # Inside inherit (outside parens): define the name
      if state.inInherit && state.inheritParenDepth == 0 then
        emitDef state tok (sym.variableSymbol packageName tok.value) KIND_VARIABLE

      # let NAME = → variable definition
      else if prev.value == "let" && next.value == "=" && next2.value != "=" then
        emitDef state tok (sym.variableSymbol packageName tok.value) KIND_VARIABLE

      # NAME : → lambda parameter
      else if next.value == ":" then
        let
          paramSym = sym.localSymbol state.localCounter;
          occ = {
            range = [tok.line tok.col tok.endCol];
            symbol = paramSym;
            symbolRoles = ROLE_DEFINITION + ROLE_WRITE;
          };
          symInfo = {
            symbol = paramSym;
            kind = KIND_PARAMETER;
            displayName = tok.value;
          };
        in state // {
          occurrences = state.occurrences ++ [occ];
          symbols = state.symbols ++ [symInfo];
          defs = state.defs // { ${tok.value} = paramSym; };
          localCounter = state.localCounter + 1;
        }

      # NAME = (not ==) → attribute binding
      else if next.value == "=" && next2.value != "=" then
        let
          valueStart = tokenAt (i + 2);
          isFunc =
            (valueStart.group == 1 && (tokenAt (i + 3)).value == ":")
            || (valueStart.value == "{" && isPatternBrace (i + 2));
          kind =
            if isFlake && builtins.hasAttr tok.value flakeOutputModules then KIND_MODULE
            else if isFlake && tok.value == "outputs" then KIND_FUNCTION
            else if isFlake && tok.value == "description" then KIND_CONSTANT
            else if isFlake && tok.value == "inputs" then KIND_MODULE
            else if isFunc then KIND_FUNCTION
            else KIND_VARIABLE;
          defSym =
            if kind == KIND_MODULE then sym.moduleSymbol packageName tok.value
            else if kind == KIND_FUNCTION then sym.functionSymbol packageName tok.value
            else sym.variableSymbol packageName tok.value;
        in emitDef state tok defSym kind

      # NAME.NAME → field reference (after a dot)
      else if prev.value == "." then
        emitRef state tok (sym.variableSymbol packageName tok.value) ROLE_READ

      # import NAME → import reference
      else if prev.value == "import" then
        emitRef state tok (sym.moduleSymbol packageName tok.value) ROLE_IMPORT

      # Known reference
      else if builtins.hasAttr tok.value state.defs then
        emitRef state tok state.defs.${tok.value} ROLE_READ

      else state

    else state
  ) initialState (builtins.genList (i: { idx = i; tok = tokenAt i; }) tokenCount);

  result = analyze;

in
{
  inherit relativePath;
  language = "nix";
  occurrences = result.occurrences;
  symbols = result.symbols;
}
