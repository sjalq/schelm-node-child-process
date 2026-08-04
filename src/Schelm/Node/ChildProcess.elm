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
    , CleanupReason(..), Cleanup(..), CapturedOutput(..), Final, RunFailure, RunError(..), ShutdownReport
    )

{-| Validated child-process data. Constructors that carry host strings or bounds are opaque.
@docs Program, Argument, WorkingDirectory, Environment, ByteLimit, Duration
@docs program, argument, workingDirectory, inheritedWorkingDirectory, inheritedEnvironment, mergeEnvironment, replaceEnvironment, byteLimit, milliseconds
@docs Stdin, StreamOutput, RunStdin, RunOutput, Deadline, SpawnOptions, RunOptions, defaultSpawnOptions, defaultRunOptions
@docs withSpawnWorkingDirectory, withSpawnEnvironment, withSpawnStdin, withSpawnStdout, withSpawnStderr, withSpawnGrace
@docs withRunWorkingDirectory, withRunEnvironment, withRunStdin, withRunStdout, withRunStderr, withRunDeadline, withRunGrace
@docs programString, argumentsStrings, spawnFacts, runFacts
@docs ConfigurationError, IdentifierKind, CreateError, SpawnError, ControlError, ReadResult, ReadError, WriteError, LeaderTermination, ProcessInfo, CleanupReason, Cleanup, CapturedOutput, Final, RunFailure, RunError, ShutdownReport
-}
import Bytes exposing (Bytes)
import Dict exposing (Dict)

type Program = Program String
type Argument = Argument String
type WorkingDirectory = InheritWorkingDirectory | WorkingDirectory String
type Environment = InheritEnvironment | MergeEnvironment (Dict String String) | ReplaceEnvironment (Dict String String)
type ByteLimit = ByteLimit Int
type Duration = Duration Int

type ConfigurationError = EmptyProgram | ContainsNul String | InvalidEnvironmentKey String
type IdentifierKind = SupervisorIdentifier | OperationIdentifier | RequestIdentifier
type CreateError = UnsupportedPlatform | IdentifierExhausted IdentifierKind | UnsupportedRuntime String
type SpawnError = InvalidConfiguration ConfigurationError | ExecutableNotFound | PermissionDenied | WorkingDirectoryNotFound | ResourceExhausted | IdentifierExhaustedOnSpawn IdentifierKind | SpawnFailed String
type ControlError = UnknownOperation | OperationCancelling | IdentifierExhaustedOnControl IdentifierKind

type Stdin = ClosedStdin | InheritStdin | InputBytes Bytes | StreamStdin
type StreamOutput = InheritStream | DiscardStream | DemandStream
type RunStdin = RunClosedStdin | RunInheritStdin | RunInputBytes Bytes
type RunOutput = InheritRunOutput | DiscardRunOutput | CaptureUpTo ByteLimit
type Deadline = NoDeadline | DeadlineAfter Duration

type SpawnOptions = SpawnOptions WorkingDirectory Environment Stdin StreamOutput StreamOutput Duration
type RunOptions = RunOptions WorkingDirectory Environment RunStdin RunOutput RunOutput Deadline Duration

type ReadResult = Chunk Bytes | End
type ReadError = ReadUnknownOperation | ReadUnavailable | ReadAlreadyPending | ReadCancelled CleanupReason | ReadTransportFailed String
type WriteError = WriteUnknownOperation | StdinUnavailable | WriteAlreadyPending | StdinAlreadyClosed | BrokenPipe | WriteCancelled CleanupReason | WriteTransportFailed String

type LeaderTermination = Exited Int | Signaled String | ExitUnknown
type alias ProcessInfo = { pid : Int }
type CleanupReason = LeaderFinished | ExplicitCancel | DeadlineReached | SupervisorShutdown | OutputOverflowStdout | OutputOverflowStderr | InputTransportFailed | ProcessTransportFailed
type Cleanup = CleanupObservedGone | CleanupUncertain String
type CapturedOutput = NotCaptured | Captured Bytes
type alias Final = { leader : LeaderTermination, cleanupReason : CleanupReason, cleanup : Cleanup, stdout : CapturedOutput, stderr : CapturedOutput }
type alias RunFailure = { leader : Maybe LeaderTermination, cleanup : Cleanup, stdout : CapturedOutput, stderr : CapturedOutput }
type RunError = RunCancelled RunFailure | RunDeadline RunFailure | RunOverflow RunFailure | RunInputError WriteError RunFailure | RunTransportError String RunFailure
type alias ShutdownReport = { operationsFinished : Int }

program s = if s == "" then Err EmptyProgram else validate "program" s |> Result.map (\_ -> Program s)
argument s = validate "argument" s |> Result.map (\_ -> Argument s)
workingDirectory s = validate "working directory" s |> Result.map (\_ -> WorkingDirectory s)
inheritedWorkingDirectory = InheritWorkingDirectory
inheritedEnvironment = InheritEnvironment
mergeEnvironment d = validateEnv d |> Result.map (\_ -> MergeEnvironment d)
replaceEnvironment d = validateEnv d |> Result.map (\_ -> ReplaceEnvironment d)
byteLimit n = if n >= 0 && n <= maxSafe then Just (ByteLimit n) else Nothing
milliseconds n = if n >= 0 && n <= maxSafe then Just (Duration n) else Nothing
maxSafe = 9007199254740990
validate label s = if String.contains "\u{0000}" s then Err (ContainsNul label) else Ok ()
validateEnv d = Dict.foldl (\k v acc -> acc |> Result.andThen (\_ -> if k == "" then Err (InvalidEnvironmentKey k) else validate "environment" (k ++ v))) (Ok ()) d

defaultGrace = Duration 500
defaultLimit = ByteLimit (1024 * 1024)
defaultDeadline = DeadlineAfter (Duration 120000)
defaultSpawnOptions = SpawnOptions InheritWorkingDirectory InheritEnvironment ClosedStdin DemandStream DemandStream defaultGrace
defaultRunOptions = RunOptions InheritWorkingDirectory InheritEnvironment RunClosedStdin (CaptureUpTo defaultLimit) (CaptureUpTo defaultLimit) defaultDeadline defaultGrace
withSpawnWorkingDirectory x (SpawnOptions _ b c d e f) = SpawnOptions x b c d e f
withSpawnEnvironment x (SpawnOptions a _ c d e f) = SpawnOptions a x c d e f
withSpawnStdin x (SpawnOptions a b _ d e f) = SpawnOptions a b x d e f
withSpawnStdout x (SpawnOptions a b c _ e f) = SpawnOptions a b c x e f
withSpawnStderr x (SpawnOptions a b c d _ f) = SpawnOptions a b c d x f
withSpawnGrace x (SpawnOptions a b c d e _) = SpawnOptions a b c d e x
withRunWorkingDirectory x (RunOptions _ b c d e f g) = RunOptions x b c d e f g
withRunEnvironment x (RunOptions a _ c d e f g) = RunOptions a x c d e f g
withRunStdin x (RunOptions a b _ d e f g) = RunOptions a b x d e f g
withRunStdout x (RunOptions a b c _ e f g) = RunOptions a b c x e f g
withRunStderr x (RunOptions a b c d _ f g) = RunOptions a b c d x f g
withRunDeadline x (RunOptions a b c d e _ g) = RunOptions a b c d e x g
withRunGrace x (RunOptions a b c d e f _) = RunOptions a b c d e f x
programString (Program s) = s
argumentsStrings = List.map (\(Argument s) -> s)
spawnFacts (SpawnOptions cwd env stdin stdout stderr (Duration grace)) = { cwd = cwdFact cwd, env = envFact env, stdin = stdinFact stdin, stdout = streamFact stdout, stderr = streamFact stderr, grace = grace, deadline = 0 }
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
