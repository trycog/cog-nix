# Hand-rolled protobuf encoder — outputs hex string
# Ported from cog-ruby's protobuf.rb
let
  # Wire types
  WIRE_VARINT = 0;
  WIRE_DELIMITED = 2;

  # Hex encoding
  hexDigits = "0123456789abcdef";

  byteToHex = b:
    let
      hi = b / 16;
      lo = b - hi * 16;
    in
    builtins.substring hi 1 hexDigits + builtins.substring lo 1 hexDigits;

  varintHex = value:
    if value < 128 then byteToHex value
    else
      byteToHex (builtins.bitOr (builtins.bitAnd value 127) 128) + varintHex (value / 128);

  tagHex = fieldNumber: wireType:
    varintHex (fieldNumber * 8 + wireType);

  # Character-to-hex lookup table (ASCII)
  charHexTable = {
    "\t" = "09"; "\n" = "0a"; "\r" = "0d";
    " " = "20"; "!" = "21"; "\"" = "22"; "#" = "23"; "$" = "24";
    "%" = "25"; "&" = "26"; "'" = "27"; "(" = "28"; ")" = "29";
    "*" = "2a"; "+" = "2b"; "," = "2c"; "-" = "2d"; "." = "2e"; "/" = "2f";
    "0" = "30"; "1" = "31"; "2" = "32"; "3" = "33"; "4" = "34";
    "5" = "35"; "6" = "36"; "7" = "37"; "8" = "38"; "9" = "39";
    ":" = "3a"; ";" = "3b"; "<" = "3c"; "=" = "3d"; ">" = "3e"; "?" = "3f";
    "@" = "40";
    "A" = "41"; "B" = "42"; "C" = "43"; "D" = "44"; "E" = "45";
    "F" = "46"; "G" = "47"; "H" = "48"; "I" = "49"; "J" = "4a";
    "K" = "4b"; "L" = "4c"; "M" = "4d"; "N" = "4e"; "O" = "4f";
    "P" = "50"; "Q" = "51"; "R" = "52"; "S" = "53"; "T" = "54";
    "U" = "55"; "V" = "56"; "W" = "57"; "X" = "58"; "Y" = "59";
    "Z" = "5a";
    "[" = "5b"; "\\" = "5c"; "]" = "5d"; "^" = "5e"; "_" = "5f"; "`" = "60";
    "a" = "61"; "b" = "62"; "c" = "63"; "d" = "64"; "e" = "65";
    "f" = "66"; "g" = "67"; "h" = "68"; "i" = "69"; "j" = "6a";
    "k" = "6b"; "l" = "6c"; "m" = "6d"; "n" = "6e"; "o" = "6f";
    "p" = "70"; "q" = "71"; "r" = "72"; "s" = "73"; "t" = "74";
    "u" = "75"; "v" = "76"; "w" = "77"; "x" = "78"; "y" = "79";
    "z" = "7a";
    "{" = "7b"; "|" = "7c"; "}" = "7d"; "~" = "7e";
  };

  charToHex = ch: charHexTable.${ch} or "3f"; # fallback to '?'

  stringToHex = str:
    let
      len = builtins.stringLength str;
      chars = builtins.genList (i: builtins.substring i 1 str) len;
    in
    builtins.concatStringsSep "" (map charToHex chars);

  # Field encoders (skip default-value fields per protobuf convention)
  encodeStringField = fieldNumber: value:
    if value == "" then ""
    else
      let
        len = builtins.stringLength value;
        hex = stringToHex value;
      in
      tagHex fieldNumber WIRE_DELIMITED + varintHex len + hex;

  encodeInt32Field = fieldNumber: value:
    if value == 0 then ""
    else tagHex fieldNumber WIRE_VARINT + varintHex value;

  encodeBoolField = fieldNumber: value:
    if !value then ""
    else tagHex fieldNumber WIRE_VARINT + varintHex 1;

  encodeMessageField = fieldNumber: dataHex:
    if dataHex == "" then ""
    else
      let byteLen = builtins.stringLength dataHex / 2;
      in tagHex fieldNumber WIRE_DELIMITED + varintHex byteLen + dataHex;

  encodePackedInt32Field = fieldNumber: values:
    if values == [] then ""
    else
      let
        packedHex = builtins.concatStringsSep "" (map varintHex values);
        byteLen = builtins.stringLength packedHex / 2;
      in
      tagHex fieldNumber WIRE_DELIMITED + varintHex byteLen + packedHex;

  encodeRepeatedMessageField = fieldNumber: messageHexes:
    if messageHexes == [] then ""
    else
      builtins.concatStringsSep "" (map (msgHex:
        let byteLen = builtins.stringLength msgHex / 2;
        in tagHex fieldNumber WIRE_DELIMITED + varintHex byteLen + msgHex
      ) messageHexes);

  encodeRepeatedStringField = fieldNumber: strings:
    if strings == [] then ""
    else
      builtins.concatStringsSep "" (map (s:
        let
          len = builtins.stringLength s;
          hex = stringToHex s;
        in
        tagHex fieldNumber WIRE_DELIMITED + varintHex len + hex
      ) strings);

  # SCIP message encoders

  encodeToolInfo = t:
    encodeStringField 1 (t.name or "")
    + encodeStringField 2 (t.version or "")
    + encodeRepeatedStringField 3 (t.arguments or []);

  encodeMetadata = m:
    encodeInt32Field 1 (m.version or 0)
    + encodeMessageField 2 (encodeToolInfo (m.toolInfo or {}))
    + encodeStringField 3 (m.projectRoot or "")
    + encodeInt32Field 4 (m.textDocumentEncoding or 0);

  encodeOccurrence = o:
    encodePackedInt32Field 1 (o.range or [])
    + encodeStringField 2 (o.symbol or "")
    + encodeInt32Field 3 (o.symbolRoles or 0)
    + encodeInt32Field 5 (o.syntaxKind or 0)
    + encodePackedInt32Field 7 (o.enclosingRange or []);

  encodeRelationship = r:
    encodeStringField 1 (r.symbol or "")
    + encodeBoolField 2 (r.isReference or false)
    + encodeBoolField 3 (r.isImplementation or false)
    + encodeBoolField 4 (r.isTypeDefinition or false)
    + encodeBoolField 5 (r.isDefinition or false)
    + encodeStringField 6 (r.kind or "");

  encodeSymbolInformation = s:
    encodeStringField 1 (s.symbol or "")
    + encodeRepeatedStringField 3 (s.documentation or [])
    + encodeRepeatedMessageField 4 (map encodeRelationship (s.relationships or []))
    + encodeInt32Field 5 (s.kind or 0)
    + encodeStringField 6 (s.displayName or "")
    + encodeStringField 8 (s.enclosingSymbol or "");

  encodeDocument = d:
    encodeStringField 1 (d.relativePath or "")
    + encodeRepeatedMessageField 2 (map encodeOccurrence (d.occurrences or []))
    + encodeRepeatedMessageField 3 (map encodeSymbolInformation (d.symbols or []))
    + encodeStringField 4 (d.language or "");

  encodeIndex = index:
    encodeMessageField 1 (encodeMetadata (index.metadata or {}))
    + encodeRepeatedMessageField 2 (map encodeDocument (index.documents or []))
    + encodeRepeatedMessageField 3 (map encodeSymbolInformation (index.externalSymbols or []));

in
{
  inherit encodeIndex encodeDocument encodeOccurrence encodeSymbolInformation
          encodeMetadata encodeToolInfo encodeRelationship
          varintHex byteToHex stringToHex charToHex;
}
