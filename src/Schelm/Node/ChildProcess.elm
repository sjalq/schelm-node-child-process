module Schelm.Node.ChildProcess exposing
    ( Program, Argument, WorkingDirectory, Environment, ByteLimit, Duration
    , program, argument, workingDirectory, inheritedWorkingDirectory
    , inheritedEnvironment, mergeEnvironment, replaceEnvironment, byteLimit, milliseconds
    , Stdin(..), StreamOutput(..), RunStdin(..), RunOutput(..), Deadline(..)
    , SpawnOptions, RunOptions, defaultSpawnOptions, defaultRunOptions
    , withSpawnWorkingDirectory, withSpawnEnvironment, withSpawnStdin, withSpawnStdout, withSpawnStderr, withSpawnGrace
    , withRunWorkingDirectory, withRunEnvironment, withRunStdin, withRunStdout, withRunStderr, withRunDeadline, withRunGrace
    , programString, argumentsStrings, spawnFacts, runFacts
    , ConfigurationError(..), IdentifierKind(..), CreateError(..), SpawnError(..), ControlError(..)
    , ReadResult(..), ReadError(..), WriteError(..), LeaderTermination(..), ProcessInfo
    , CleanupReason(..), SignalResult(..), ProbeResult(..), Cleanup(..), CapturedOutput(..), Final, RunFailure, RunError(..), ShutdownReport
    )

{-| Validated child-process data. Constructors that carry host strings or bounds are opaque.
@docs Program, Argument, WorkingDirectory, Environment, ByteLimit, Duration
@docs program, argument, workingDirectory, inheritedWorkingDirectory, inheritedEnvironment, mergeEnvironment, replaceEnvironment, byteLimit, milliseconds
@docs Stdin, StreamOutput, RunStdin, RunOutput, Deadline, SpawnOptions, RunOptions, defaultSpawnOptions, defaultRunOptions
@docs withSpawnWorkingDirectory, withSpawnEnvironment, withSpawnStdin, withSpawnStdout, withSpawnStderr, withSpawnGrace
@docs withRunWorkingDirectory, withRunEnvironment, withRunStdin, withRunStdout, withRunStderr, withRunDeadline, withRunGrace
@docs programString, argumentsStrings, spawnFacts, runFacts
@docs ConfigurationError, IdentifierKind, CreateError, SpawnError, ControlError, ReadResult, ReadError, WriteError, LeaderTermination, ProcessInfo, CleanupReason, SignalResult, ProbeResult, Cleanup, CapturedOutput, Final, RunFailure, RunError, ShutdownReport
-}
import Bytes exposing (Bytes)
import Dict exposing (Dict)

{-| Validated executable. -}
type Program = Program String
{-| Validated literal argv element. -}
type Argument = Argument String
{-| Inherited or validated cwd. -}
type WorkingDirectory = InheritWorkingDirectory | WorkingDirectory String
{-| Inherited, merged, or replacement environment. -}
type Environment = InheritEnvironment | MergeEnvironment (Dict String String) | ReplaceEnvironment (Dict String String)
{-| Nonnegative safe byte bound. -}
type ByteLimit = ByteLimit Int
{-| Nonnegative safe millisecond duration. -}
type Duration = Duration Int

{-| Builder validation failure. -}
type ConfigurationError = EmptyProgram | ContainsNul String | InvalidEnvironmentKey String
{-| Exhaustible monotonic identifier domain. -}
type IdentifierKind = SupervisorIdentifier | OperationIdentifier | RequestIdentifier
{-| Supervisor creation failure. -}
type CreateError = UnsupportedPlatform | IdentifierExhausted IdentifierKind | UnsupportedRuntime String
{-| Failure before a started operation exists. -}
type SpawnError = InvalidConfiguration ConfigurationError | ExecutableNotFound | PermissionDenied | WorkingDirectoryNotFound | ResourceExhausted | IdentifierExhaustedOnSpawn IdentifierKind | SpawnFailed String
{-| Operation/supervisor control failure. -}
type ControlError = UnknownOperation | OperationCancelling | IdentifierExhaustedOnControl IdentifierKind

{-| Spawn stdin mode. -}
type Stdin = ClosedStdin | InheritStdin | InputBytes Bytes | StreamStdin
{-| Demand-streamed spawn output mode. -}
type StreamOutput = InheritStream | DiscardStream | DemandStream
{-| Buffered run stdin mode. -}
type RunStdin = RunClosedStdin | RunInheritStdin | RunInputBytes Bytes
{-| Buffered run output mode. -}
type RunOutput = InheritRunOutput | DiscardRunOutput | CaptureUpTo ByteLimit
{-| Buffered run deadline. -}
type Deadline = NoDeadline | DeadlineAfter Duration

{-| Opaque streamed-spawn options. -}
type SpawnOptions = SpawnOptions WorkingDirectory Environment Stdin StreamOutput StreamOutput Duration
{-| Opaque buffered-run options. -}
type RunOptions = RunOptions WorkingDirectory Environment RunStdin RunOutput RunOutput Deadline Duration

{-| One demanded stream result. -}
type ReadResult = Chunk Bytes | End
{-| Demand failure. -}
type ReadError = ReadUnknownOperation | ReadUnavailable | ReadAlreadyPending | ReadCancelled CleanupReason | ReadTransportFailed String
{-| Streamed stdin failure. -}
type WriteError = WriteUnknownOperation | StdinUnavailable | WriteAlreadyPending | StdinAlreadyClosed | BrokenPipe | WriteCancelled CleanupReason | WriteTransportFailed String

{-| Direct leader terminal fact. -}
type LeaderTermination = Exited Int | Signaled String | ExitUnknown
{-| Observational leader facts; PID is not authority. -}
type alias ProcessInfo = { pid : Int }
{-| First manager-routed cleanup initiator. -}
type CleanupReason = LeaderFinished | ExplicitCancel | DeadlineReached | SupervisorShutdown | OutputOverflowStdout | OutputOverflowStderr | InputTransportFailed | ProcessTransportFailed
{-| One attempted group signal syscall. -}
type SignalResult
    = SignalSent
    | SignalFailed String

{-| One fixed post-KILL group probe. -}
type ProbeResult
    = ProbePresent
    | ProbeGone
    | ProbeFailed String

{-| Lossless TERM/KILL/probe evidence and final classification. -}
type Cleanup
    = CleanupObservedGone
        { term : SignalResult
        , kill : SignalResult
        , probes : List ProbeResult
        }
    | CleanupUncertain
        { term : SignalResult
        , kill : SignalResult
        , probes : List ProbeResult
        , detail : String
        }
{-| Explicit capture accessibility. -}
type CapturedOutput = NotCaptured | Captured Bytes
{-| Exactly-once final operation result. -}
type alias Final = { leader : LeaderTermination, cleanupReason : CleanupReason, cleanup : Cleanup, transportDetail : Maybe String, stdout : CapturedOutput, stderr : CapturedOutput }
{-| Bounded partial result on run failure. -}
type alias RunFailure = { leader : Maybe LeaderTermination, cleanup : Cleanup, stdout : CapturedOutput, stderr : CapturedOutput }
{-| Buffered run failure after start. -}
type RunError = RunCancelled RunFailure | RunDeadline RunFailure | RunOverflow RunFailure | RunInputError WriteError RunFailure | RunTransportError String RunFailure
{-| Explicit supervisor shutdown report. -}
type alias ShutdownReport = { operationsFinished : Int }

{-| Validate an executable. -}
program : String -> Result ConfigurationError Program
program s = if s == "" then Err EmptyProgram else validate "program" s |> Result.map (\_ -> Program s)
{-| Validate one literal argument. -}
argument : String -> Result ConfigurationError Argument
argument s = validate "argument" s |> Result.map (\_ -> Argument s)
{-| Validate a cwd. -}
workingDirectory : String -> Result ConfigurationError WorkingDirectory
workingDirectory s = validate "working directory" s |> Result.map (\_ -> WorkingDirectory s)
{-| Inherit the parent cwd. -}
inheritedWorkingDirectory : WorkingDirectory
inheritedWorkingDirectory = InheritWorkingDirectory
{-| Inherit the parent environment. -}
inheritedEnvironment : Environment
inheritedEnvironment = InheritEnvironment
{-| Validate variables merged over the parent environment. -}
mergeEnvironment : Dict String String -> Result ConfigurationError Environment
mergeEnvironment d = validateEnv d |> Result.map (\_ -> MergeEnvironment d)
{-| Validate a replacement environment. -}
replaceEnvironment : Dict String String -> Result ConfigurationError Environment
replaceEnvironment d = validateEnv d |> Result.map (\_ -> ReplaceEnvironment d)
{-| Construct a safe byte limit. -}
byteLimit : Int -> Maybe ByteLimit
byteLimit n = if n >= 0 && n <= maxSafe then Just (ByteLimit n) else Nothing
{-| Construct a safe duration. -}
milliseconds : Int -> Maybe Duration
milliseconds n = if n >= 0 && n <= maxSafe then Just (Duration n) else Nothing
maxSafe = 9007199254740990
validate label s = if String.contains "\u{0000}" s then Err (ContainsNul label) else Ok ()
validateEnv d = Dict.foldl (\k v acc -> acc |> Result.andThen (\_ -> if k == "" then Err (InvalidEnvironmentKey k) else validate "environment" (k ++ v))) (Ok ()) d

defaultGrace = Duration 500
defaultLimit = ByteLimit (1024 * 1024)
defaultDeadline = DeadlineAfter (Duration 120000)
{-| Demand-output, closed-stdin default spawn options. -}
defaultSpawnOptions : SpawnOptions
defaultSpawnOptions = SpawnOptions InheritWorkingDirectory InheritEnvironment ClosedStdin DemandStream DemandStream defaultGrace
{-| Bounded-capture buffered run defaults. -}
defaultRunOptions : RunOptions
defaultRunOptions = RunOptions InheritWorkingDirectory InheritEnvironment RunClosedStdin (CaptureUpTo defaultLimit) (CaptureUpTo defaultLimit) defaultDeadline defaultGrace
{-| Set spawn cwd. -}
withSpawnWorkingDirectory : WorkingDirectory -> SpawnOptions -> SpawnOptions
withSpawnWorkingDirectory x (SpawnOptions _ b c d e f) = SpawnOptions x b c d e f
{-| Set spawn environment. -}
withSpawnEnvironment : Environment -> SpawnOptions -> SpawnOptions
withSpawnEnvironment x (SpawnOptions a _ c d e f) = SpawnOptions a x c d e f
{-| Set spawn stdin. -}
withSpawnStdin : Stdin -> SpawnOptions -> SpawnOptions
withSpawnStdin x (SpawnOptions a b _ d e f) = SpawnOptions a b x d e f
{-| Set spawn stdout. -}
withSpawnStdout : StreamOutput -> SpawnOptions -> SpawnOptions
withSpawnStdout x (SpawnOptions a b c _ e f) = SpawnOptions a b c x e f
{-| Set spawn stderr. -}
withSpawnStderr : StreamOutput -> SpawnOptions -> SpawnOptions
withSpawnStderr x (SpawnOptions a b c d _ f) = SpawnOptions a b c d x f
{-| Set spawn cleanup grace. -}
withSpawnGrace : Duration -> SpawnOptions -> SpawnOptions
withSpawnGrace x (SpawnOptions a b c d e _) = SpawnOptions a b c d e x
{-| Set run cwd. -}
withRunWorkingDirectory : WorkingDirectory -> RunOptions -> RunOptions
withRunWorkingDirectory x (RunOptions _ b c d e f g) = RunOptions x b c d e f g
{-| Set run environment. -}
withRunEnvironment : Environment -> RunOptions -> RunOptions
withRunEnvironment x (RunOptions a _ c d e f g) = RunOptions a x c d e f g
{-| Set run stdin. -}
withRunStdin : RunStdin -> RunOptions -> RunOptions
withRunStdin x (RunOptions a b _ d e f g) = RunOptions a b x d e f g
{-| Set run stdout capture mode. -}
withRunStdout : RunOutput -> RunOptions -> RunOptions
withRunStdout x (RunOptions a b c _ e f g) = RunOptions a b c x e f g
{-| Set run stderr capture mode. -}
withRunStderr : RunOutput -> RunOptions -> RunOptions
withRunStderr x (RunOptions a b c d _ f g) = RunOptions a b c d x f g
{-| Set run deadline. -}
withRunDeadline : Deadline -> RunOptions -> RunOptions
withRunDeadline x (RunOptions a b c d e _ g) = RunOptions a b c d e x g
{-| Set run cleanup grace. -}
withRunGrace : Duration -> RunOptions -> RunOptions
withRunGrace x (RunOptions a b c d e f _) = RunOptions a b c d e f x
{-| Internal stable executable fact. -}
programString : Program -> String
programString (Program s) = s
{-| Internal stable argv facts. -}
argumentsStrings : List Argument -> List String
argumentsStrings = List.map (\(Argument s) -> s)
{-| Internal spawn boundary facts. -}
spawnFacts : SpawnOptions -> { cwd : Maybe String, env : ( Int, List ( String, String ) ), stdin : ( Int, Maybe Bytes ), stdout : Int, stderr : Int, grace : Int, deadline : Int }
spawnFacts (SpawnOptions cwd env stdin stdout stderr (Duration grace)) = { cwd = cwdFact cwd, env = envFact env, stdin = stdinFact stdin, stdout = streamFact stdout, stderr = streamFact stderr, grace = grace, deadline = 0 }
{-| Internal run boundary facts. -}
runFacts : RunOptions -> { cwd : Maybe String, env : ( Int, List ( String, String ) ), stdin : ( Int, Maybe Bytes ), stdout : ( Int, Int ), stderr : ( Int, Int ), deadline : Int, grace : Int }
runFacts (RunOptions cwd env stdin stdout stderr deadline (Duration grace)) = { cwd = cwdFact cwd, env = envFact env, stdin = runStdinFact stdin, stdout = runOutputFact stdout, stderr = runOutputFact stderr, deadline = deadlineFact deadline, grace = grace }
cwdFact x =
    case x of
        InheritWorkingDirectory -> Nothing
        WorkingDirectory s -> Just s
envFact x =
    case x of
        InheritEnvironment -> ( 0, [] )
        MergeEnvironment d -> ( 1, Dict.toList d )
        ReplaceEnvironment d -> ( 2, Dict.toList d )
stdinFact x =
    case x of
        ClosedStdin -> ( 0, Nothing )
        InheritStdin -> ( 1, Nothing )
        InputBytes b -> ( 2, Just b )
        StreamStdin -> ( 3, Nothing )
streamFact x =
    case x of
        InheritStream -> 0
        DiscardStream -> 1
        DemandStream -> 2
runStdinFact x =
    case x of
        RunClosedStdin -> ( 0, Nothing )
        RunInheritStdin -> ( 1, Nothing )
        RunInputBytes b -> ( 2, Just b )
runOutputFact x =
    case x of
        InheritRunOutput -> ( 0, 0 )
        DiscardRunOutput -> ( 1, 0 )
        CaptureUpTo (ByteLimit n) -> ( 2, n )
deadlineFact x =
    case x of
        NoDeadline -> 0
        DeadlineAfter (Duration n) -> n
