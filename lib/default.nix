# cog-nix entry point
# Takes: { files, projectRoot, packageName, toolVersion }
# Returns: hex-encoded SCIP protobuf index

{ files, projectRoot, packageName, toolVersion }:
let
  encode = import ./encode.nix;

  # Compute relative path by stripping projectRoot prefix
  stripPrefix = prefix: path:
    let
      prefixLen = builtins.stringLength prefix;
      pathLen = builtins.stringLength path;
      prefixWithSlash = if builtins.substring (prefixLen - 1) 1 prefix == "/"
                        then prefix
                        else prefix + "/";
      pfxLen = builtins.stringLength prefixWithSlash;
    in
    if pfxLen <= pathLen && builtins.substring 0 pfxLen path == prefixWithSlash
    then builtins.substring pfxLen (pathLen - pfxLen) path
    else path;

  # Get the basename of a path
  basename = path:
    let
      parts = builtins.filter builtins.isString (builtins.split "/" path);
      n = builtins.length parts;
    in
    if n == 0 then path
    else builtins.elemAt parts (n - 1);

  processFile = filePath:
    let
      source = builtins.readFile filePath;
      relPath = stripPrefix projectRoot filePath;
      fname = basename filePath;
    in
    import ./analyze.nix {
      inherit source packageName;
      relativePath = relPath;
      filename = fname;
    };

  documents = map processFile files;

  index = {
    metadata = {
      version = 1;  # ProtocolVersion.Scip0
      toolInfo = {
        name = "cog-nix";
        version = toolVersion;
        arguments = [];
      };
      projectRoot = "file://${projectRoot}";
      textDocumentEncoding = 0;  # UTF8
    };
    inherit documents;
    externalSymbols = [];
  };

in
encode.encodeIndex index
