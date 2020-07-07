Program = new Type of HashTable
ProgramRun = new Type of HashTable
programPaths = new MutableHashTable

-- we expect a trailing slash in the path, but the paths given in the
-- PATH environment variable likely will not have one, so we add one
-- if needed
addSlash = programPath -> (
    if last programPath != "/" then return programPath | "/"
    else return programPath
)

checkProgramPath = (name, cmds, programPath, opts) -> (
    if opts.Verbose == true then
	print("checking for " | name | " in " | programPath | "...");
    if all(cmds, cmd -> run(programPath | cmd | " >/dev/null 2>&1") == 0) then (
	if opts.Verbose == true then print("	found");
	return true;
    ) else (
	if opts.Verbose == true then print("	not found");
	return false;
    )
)

getProgramPath = (name, cmds, opts) -> (
    pathsToTry := {};
    -- try user-configured path first
    if programPaths#?name then
	pathsToTry = append(pathsToTry, programPaths#name);
    -- now try M2-installed path
    pathsToTry = append(pathsToTry, prefixDirectory | currentLayout#"programs");
    -- finally, try PATH
    if getenv "PATH" != "" then
	pathsToTry = join(pathsToTry, separate(":", getenv "PATH"));
    pathsToTry = apply(pathsToTry, addSlash);
    scan(pathsToTry, pathToTry ->
	if checkProgramPath(name, cmds, pathToTry, opts) then
	    break pathToTry)
)

loadProgram = method(TypicalValue => Program,
    Options => {RaiseError => true, Verbose => false})
loadProgram(String, String) := opts -> (name, cmd) ->
    loadProgram(name, {cmd}, opts)
loadProgram(String, List) := opts -> (name, cmds) -> (
    programPath := getProgramPath(name, cmds, opts);
    if programPath === null then
	if opts.RaiseError then error("could not find " | name)
	else return null;
    new Program from {"name" => name, "path" => programPath}
)

runProgram = method(TypicalValue => ProgramRun,
    Options => {RaiseError => true, KeepFiles => false, Verbose => false})
runProgram(Program, String) := opts -> (program, args) ->
    runProgram(program, program#"name", args, opts)
runProgram(Program, String, String) := opts -> (program, name, args) -> (
    tmpFile := temporaryFileName();
    outFile := tmpFile | ".out";
    errFile := tmpFile | ".err";
    cmd := program#"path" | name | " " | args;
    returnValue := run (cmd | " > " | outFile | " 2> " | errFile);
    message := "running: " | cmd | "\n";
    output := get outFile;
    if output != "" then message = message | output;
    err := get errFile;
    if err != "" then message = message | err;
    if opts.Verbose then print(message);
    result := {
	"command" => cmd,
	"output" => output,
	"error" => err,
	"return value" => returnValue};
    if opts.KeepFiles then result = result | {
	"output file" => outFile,
	"error file" => errFile}
    else (
	removeFile outFile;
	removeFile errFile;
    );
    if opts.RaiseError and returnValue != 0 then error(
	program#"name" | " returned an error" |
	if opts.Verbose then "" else "\n" | message);
    new ProgramRun from result
)

net ProgramRun := pr -> net pr#"return value"
