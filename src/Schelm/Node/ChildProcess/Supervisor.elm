effect module Schelm.Node.ChildProcess.Supervisor where { command = MyCmd } exposing
    ( Supervisor, Operation, Request, SpawnCallbacks, RunCallbacks, create, createParented, spawn, run
    , demandStdout, demandStderr, writeStdin, closeStdin, cancel, shutdown
    )

{-| Manager-owned supervised operations.
@docs Supervisor, Operation, Request, SpawnCallbacks, RunCallbacks, create, createParented, spawn, run
@docs demandStdout, demandStderr, writeStdin, closeStdin, cancel, shutdown
-}

import Bytes exposing (Bytes)
import Dict exposing (Dict)
import Elm.Kernel.SchelmChildProcess
import Platform
import Platform.Cmd exposing (Cmd)
import Process
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.ParentAdapter as ParentAdapter
import Task exposing (Task)


{-| Opaque supervisor scope. -}
type Supervisor = Supervisor Int
{-| Opaque operation authority. -}
type Operation = Operation Int Int
{-| Opaque request identity. -}
type Request = Request Int Int Int

{-| Started/failure/final callbacks. -}
type alias SpawnCallbacks msg =
    { onStarted : Operation -> Child.ProcessInfo -> msg
    , onSpawnFailed : Child.SpawnError -> msg
    , onFinished : Operation -> Child.Final -> msg
    }

{-| Buffered run lifecycle callbacks. -}
type alias RunCallbacks msg =
    { onStarted : Operation -> Child.ProcessInfo -> msg
    , onSpawnFailed : Child.SpawnError -> msg
    , onFinished : Operation -> Result Child.RunError Child.Final -> msg
    }

type Callbacks msg
    = SpawnCallbacksValue (SpawnCallbacks msg)
    | RunCallbacksValue (RunCallbacks msg)

type ParentRegistration
    = Standalone
    | Parented Int Int

type OperationPhase
    = Preparing
    | Binding Int
    | Running
    | Rejecting String

type OutputFacts
    = SpawnOutput Int Int
    | RunOutput ( Int, Int ) ( Int, Int )

type alias Launch =
    { program : String
    , arguments : List String
    , cwd : Maybe String
    , env : ( Int, List ( String, String ) )
    , stdin : ( Int, Maybe Bytes )
    , output : OutputFacts
    , grace : Int
    , deadline : Int
    }

type alias Active msg =
    { supervisor : Int
    , callbacks : Callbacks msg
    , parent : ParentRegistration
    , phase : OperationPhase
    , launch : Launch
    }

type alias PendingRead msg = { supervisor : Int, operation : Int, callback : Request -> Result Child.ReadError Child.ReadResult -> msg }
type WriteKind = Writing | Closing

type StdinState = StdinIdle | StdinBusy WriteKind | StdinClosed

type alias PendingWrite msg = { supervisor : Int, operation : Int, kind : WriteKind, callback : Request -> Result Child.WriteError () -> msg }
type alias State msg =
    { nextSupervisor : Int, nextOperation : Int, nextRequest : Int
    , supervisors : Dict Int ParentRegistration, active : Dict Int (Active msg)
    , shutdowns : Dict Int { callback : Result Child.ControlError Child.ShutdownReport -> msg, total : Int }
    , reads : Dict Int (PendingRead msg), writes : Dict Int (PendingWrite msg)
    , stdinStates : Dict Int StdinState
    }

type MyCmd msg
    = Create (Result Child.CreateError Supervisor -> msg)
    | CreateParented ParentAdapter.Prepared (Result Child.CreateError Supervisor -> msg)
    | Spawn Supervisor (SpawnCallbacks msg) Child.Program (List Child.Argument) Child.SpawnOptions
    | Run Supervisor (RunCallbacks msg) Child.Program (List Child.Argument) Child.RunOptions
    | Demand Bool Operation (Request -> Result Child.ReadError Child.ReadResult -> msg)
    | Write Operation Bytes (Request -> Result Child.WriteError () -> msg)
    | Close Operation (Request -> Result Child.WriteError () -> msg)
    | Cancel Operation (Result Child.ControlError () -> msg)
    | Shutdown Supervisor (Result Child.ControlError Child.ShutdownReport -> msg)

type SelfMsg
    = BeginStart Int
    | Spawned Int (Result String Int)
    | BeginBind Int
    | ExposeStarted Int Int Int
    | ArmOperation Int
    | Finished Int Int String String String String ( String, ( String, ( String, List String ) ) ) (Maybe Bytes) (Maybe Bytes)
    | ParentBound Int (Result String ( Int, Int ))
    | ReadDone Int (Result String (Maybe Bytes))
    | WriteDone Int (Result String ())

type alias MyRouter msg = Platform.Router msg SelfMsg

{-| Create a standalone Unix supervisor. -}
create : (Result Child.CreateError Supervisor -> msg) -> Cmd msg
create cb = command (Create cb)
{-| Create a supervisor from a parent-acknowledged, single-use reservation. -}
createParented : ParentAdapter.Prepared -> (Result Child.CreateError Supervisor -> msg) -> Cmd msg
createParented prepared cb = command (CreateParented prepared cb)
{-| Spawn a demand-streamed process. -}
spawn : Supervisor -> SpawnCallbacks msg -> Child.Program -> List Child.Argument -> Child.SpawnOptions -> Cmd msg
spawn supervisor callbacks executable arguments options = command (Spawn supervisor callbacks executable arguments options)
{-| Run a buffered-mode process through the same lifecycle. -}
run : Supervisor -> RunCallbacks msg -> Child.Program -> List Child.Argument -> Child.RunOptions -> Cmd msg
run supervisor callbacks executable arguments options = command (Run supervisor callbacks executable arguments options)
{-| Demand one stdout chunk. -}
demandStdout : Operation -> (Request -> Result Child.ReadError Child.ReadResult -> msg) -> Cmd msg
demandStdout operation cb = command (Demand True operation cb)
{-| Demand one stderr chunk. -}
demandStderr : Operation -> (Request -> Result Child.ReadError Child.ReadResult -> msg) -> Cmd msg
demandStderr operation cb = command (Demand False operation cb)
{-| Write one stdin value with Node backpressure. -}
writeStdin : Operation -> Bytes -> (Request -> Result Child.WriteError () -> msg) -> Cmd msg
writeStdin operation bytes cb = command (Write operation bytes cb)
{-| Close streamed stdin. -}
closeStdin : Operation -> (Request -> Result Child.WriteError () -> msg) -> Cmd msg
closeStdin operation cb = command (Close operation cb)
{-| Join or initiate operation cleanup. -}
cancel : Operation -> (Result Child.ControlError () -> msg) -> Cmd msg
cancel operation cb = command (Cancel operation cb)
{-| Explicitly shut down a supervisor. -}
shutdown : Supervisor -> (Result Child.ControlError Child.ShutdownReport -> msg) -> Cmd msg
shutdown supervisor cb = command (Shutdown supervisor cb)

cmdMap f command_ =
    case command_ of
        Create cb -> Create (cb >> f)
        CreateParented prepared cb -> CreateParented prepared (cb >> f)
        Spawn s cb p a o -> Spawn s (mapCallbacks f cb) p a o
        Run s cb p a o -> Run s (mapRunCallbacks f cb) p a o
        Demand b op cb -> Demand b op (\r x -> f (cb r x))
        Write op bytes cb -> Write op bytes (\r x -> f (cb r x))
        Close op cb -> Close op (\r x -> f (cb r x))
        Cancel op cb -> Cancel op (cb >> f)
        Shutdown s cb -> Shutdown s (cb >> f)

mapRunCallbacks f cb =
    { onStarted = \operation info -> f (cb.onStarted operation info)
    , onSpawnFailed = cb.onSpawnFailed >> f
    , onFinished = \operation final -> f (cb.onFinished operation final)
    }

mapCallbacks f cb =
    { onStarted = \operation info -> f (cb.onStarted operation info)
    , onSpawnFailed = cb.onSpawnFailed >> f
    , onFinished = \operation final -> f (cb.onFinished operation final)
    }

maxId = 9007199254740990
init = Task.succeed { nextSupervisor = 0, nextOperation = 0, nextRequest = 0, supervisors = Dict.empty, active = Dict.empty, shutdowns = Dict.empty, reads = Dict.empty, writes = Dict.empty, stdinStates = Dict.empty }
onEffects router commands state = applyCommands router commands state

applyCommands router commands state =
    case commands of
        [] -> Task.succeed state
        first :: rest -> applyCommand router first state |> Task.andThen (applyCommands router rest)

applyCommand router command_ state =
    case command_ of
        Create cb ->
            if state.nextSupervisor >= maxId then
                send router (cb (Err (Child.IdentifierExhausted Child.SupervisorIdentifier))) state
            else if not Elm.Kernel.SchelmChildProcess.isUnix then
                send router (cb (Err Child.UnsupportedPlatform)) state
            else
                let sid = state.nextSupervisor in
                send router (cb (Ok (Supervisor sid))) { state | nextSupervisor = sid + 1, supervisors = Dict.insert sid Standalone state.supervisors }

        CreateParented prepared cb ->
            if state.nextSupervisor >= maxId then
                send router (cb (Err (Child.IdentifierExhausted Child.SupervisorIdentifier))) state
            else if not Elm.Kernel.SchelmChildProcess.isUnix then
                send router (cb (Err Child.UnsupportedPlatform)) state
            else
                let
                    sid = state.nextSupervisor
                    reservation = ParentAdapter.reservation prepared
                    parent = Parented reservation (ParentAdapter.responseTimeout prepared)
                in
                Elm.Kernel.SchelmChildProcess.parentClaim reservation
                    |> Task.andThen
                        (\claimed ->
                            if claimed then
                                send router (cb (Ok (Supervisor sid))) { state | nextSupervisor = sid + 1, supervisors = Dict.insert sid parent state.supervisors }
                            else
                                send router (cb (Err (Child.UnsupportedRuntime "parent reservation already consumed"))) state
                        )

        Spawn (Supervisor sid) cb executable arguments options ->
            let facts = Child.spawnFacts options in
            start router sid (SpawnCallbacksValue cb) executable arguments
                { cwd = facts.cwd, env = facts.env, stdin = facts.stdin, output = SpawnOutput facts.stdout facts.stderr, ipc = facts.ipc, grace = facts.grace, deadline = facts.deadline }
                state

        Run (Supervisor sid) cb executable arguments options ->
            let facts = Child.runFacts options in
            start router sid (RunCallbacksValue cb) executable arguments
                { cwd = facts.cwd, env = facts.env, stdin = facts.stdin, output = RunOutput facts.stdout facts.stderr, ipc = False, grace = facts.grace, deadline = facts.deadline }
                state

        Demand stdout (Operation sid oid) cb ->
            startRead router stdout sid oid cb state

        Write (Operation sid oid) bytes cb ->
            startWrite router sid oid bytes cb state

        Close (Operation sid oid) cb ->
            startClose router sid oid cb state

        Cancel (Operation sid oid) cb ->
            case Dict.get oid state.active of
                Just active ->
                    if active.supervisor == sid then
                        cancelOperation router oid active cb state
                    else
                        send router (cb (Err Child.UnknownOperation)) state

                Nothing ->
                    send router (cb (Err Child.UnknownOperation)) state

        Shutdown (Supervisor sid) cb ->
            if Dict.member sid state.supervisors then
                shutdownSupervisor router sid cb state
            else
                send router (cb (Err Child.UnknownOperation)) state

cancelOperation router oid active callback state =
    case active.phase of
        Preparing ->
            let
                next =
                    { state
                        | active = Dict.remove oid state.active
                        , stdinStates = Dict.remove oid state.stdinStates
                    }
            in
            sendMany router
                [ spawnFailed active.callbacks (Child.SpawnFailed "cancelled")
                , callback (Ok ())
                ]
                next

        Binding _ ->
            let
                rejecting = { active | phase = Rejecting "cancelled" }
                next = { state | active = Dict.insert oid rejecting state.active }
            in
            Elm.Kernel.SchelmChildProcess.cancel oid
                |> Task.andThen (\_ -> send router (callback (Ok ())) next)

        Running ->
            Elm.Kernel.SchelmChildProcess.cancel oid
                |> Task.andThen (\_ -> send router (callback (Ok ())) state)

        Rejecting _ ->
            send router (callback (Ok ())) state


shutdownSupervisor router sid callback state =
    let
        ownedOperations =
            Dict.toList state.active
                |> List.filter (\( _, active ) -> active.supervisor == sid)
        total = List.length ownedOperations
        preparingIds =
            ownedOperations
                |> List.filterMap
                    (\( oid, active ) ->
                        case active.phase of
                            Preparing -> Just oid
                            _ -> Nothing
                    )
        physicalIds =
            ownedOperations
                |> List.filterMap
                    (\( oid, active ) ->
                        case active.phase of
                            Preparing -> Nothing
                            Rejecting _ -> Nothing
                            _ -> Just oid
                    )
        preparingFailures =
            ownedOperations
                |> List.filterMap
                    (\( _, active ) ->
                        case active.phase of
                            Preparing -> Just (spawnFailed active.callbacks (Child.SpawnFailed "cancelled"))
                            _ -> Nothing
                    )
        abortBinding _ active =
            if active.supervisor == sid then
                case active.phase of
                    Binding _ -> { active | phase = Rejecting "cancelled" }
                    _ -> active
            else
                active
        withoutPreparing =
            List.foldl Dict.remove state.active preparingIds
        next =
            { state
                | supervisors = Dict.remove sid state.supervisors
                , active = Dict.map abortBinding withoutPreparing
                , stdinStates = List.foldl Dict.remove state.stdinStates preparingIds
            }
    in
    if List.isEmpty physicalIds then
        sendMany router
            (List.reverse (callback (Ok { operationsFinished = total }) :: List.reverse preparingFailures))
            next
    else
        Elm.Kernel.SchelmChildProcess.cancelMany physicalIds
            |> Task.andThen
                (\_ ->
                    sendMany router preparingFailures
                        { next
                            | shutdowns =
                                Dict.insert sid { callback = callback, total = total } next.shutdowns
                        }
                )


start router sid cb executable arguments facts state =
    case Dict.get sid state.supervisors of
        Nothing ->
            send router (spawnFailed cb (Child.SpawnFailed "unknown supervisor")) state

        Just parent ->
            if state.nextOperation >= maxId then
                send router (spawnFailed cb (Child.IdentifierExhaustedOnSpawn Child.OperationIdentifier)) state
            else
                let
                    oid = state.nextOperation
                    launch =
                        { program = Child.programString executable
                        , arguments = Child.argumentsStrings arguments
                        , cwd = facts.cwd
                        , env = facts.env
                        , stdin = facts.stdin
                        , output = facts.output
                        , ipc = facts.ipc
                        , grace = facts.grace
                        , deadline = facts.deadline
                        }
                    operation =
                        { supervisor = sid
                        , callbacks = cb
                        , parent = parent
                        , phase = Preparing
                        , launch = launch
                        }
                    next =
                        { state
                            | nextOperation = oid + 1
                            , active = Dict.insert oid operation state.active
                            , stdinStates = Dict.insert oid StdinIdle state.stdinStates
                        }
                in
                -- Sending the launch message is part of this manager task. The manager
                -- commits `next` before it can dequeue BeginStart; no spawned task can
                -- observe an absent operation.
                Platform.sendToSelf router (BeginStart oid)
                    |> Task.andThen (\_ -> Task.succeed next)

startRead router stdout sid oid cb state =
    case allocateRequest state of
        Nothing -> send router (cb (Request sid oid state.nextRequest) (Err (Child.ReadTransportFailed "identifier exhausted"))) state
        Just ( rid, next ) ->
            if owned sid oid state then
                Elm.Kernel.SchelmChildProcess.read oid stdout
                    |> Task.map Ok |> Task.onError (Err >> Task.succeed)
                    |> Task.andThen (ReadDone rid >> Platform.sendToSelf router) |> Process.spawn
                    |> Task.andThen (\_ -> Task.succeed { next | reads = Dict.insert rid { supervisor = sid, operation = oid, callback = cb } next.reads })
            else send router (cb (Request sid oid rid) (Err Child.ReadUnknownOperation)) next

startWrite router sid oid bytes cb state =
    case allocateRequest state of
        Nothing -> send router (cb (Request sid oid state.nextRequest) (Err (Child.WriteTransportFailed "identifier exhausted"))) state
        Just ( rid, next ) ->
            if not (owned sid oid state) then
                send router (cb (Request sid oid rid) (Err Child.WriteUnknownOperation)) next
            else
                case Dict.get oid state.stdinStates |> Maybe.withDefault StdinIdle of
                    StdinClosed -> send router (cb (Request sid oid rid) (Err Child.StdinAlreadyClosed)) next
                    StdinBusy _ -> send router (cb (Request sid oid rid) (Err Child.WriteAlreadyPending)) next
                    StdinIdle ->
                        Elm.Kernel.SchelmChildProcess.write oid bytes
                            |> Task.map Ok |> Task.onError (Err >> Task.succeed)
                            |> Task.andThen (WriteDone rid >> Platform.sendToSelf router) |> Process.spawn
                            |> Task.andThen (\_ -> Task.succeed { next | writes = Dict.insert rid { supervisor = sid, operation = oid, kind = Writing, callback = cb } next.writes, stdinStates = Dict.insert oid (StdinBusy Writing) next.stdinStates })

startClose router sid oid cb state =
    case allocateRequest state of
        Nothing -> send router (cb (Request sid oid state.nextRequest) (Err (Child.WriteTransportFailed "identifier exhausted"))) state
        Just ( rid, next ) ->
            if not (owned sid oid state) then
                send router (cb (Request sid oid rid) (Err Child.WriteUnknownOperation)) next
            else
                case Dict.get oid state.stdinStates |> Maybe.withDefault StdinIdle of
                    StdinClosed -> send router (cb (Request sid oid rid) (Err Child.StdinAlreadyClosed)) next
                    StdinBusy _ -> send router (cb (Request sid oid rid) (Err Child.WriteAlreadyPending)) next
                    StdinIdle ->
                        Elm.Kernel.SchelmChildProcess.close oid
                            |> Task.map Ok |> Task.onError (Err >> Task.succeed)
                            |> Task.andThen (WriteDone rid >> Platform.sendToSelf router) |> Process.spawn
                            |> Task.andThen (\_ -> Task.succeed { next | writes = Dict.insert rid { supervisor = sid, operation = oid, kind = Closing, callback = cb } next.writes, stdinStates = Dict.insert oid (StdinBusy Closing) next.stdinStates })

allocateRequest state = if state.nextRequest >= maxId then Nothing else Just ( state.nextRequest, { state | nextRequest = state.nextRequest + 1 } )
owned sid oid state =
    case Dict.get oid state.active of
        Just active -> active.supervisor == sid
        Nothing -> False
send router msg state =
    Platform.sendToApp router msg
        |> Task.andThen (\_ -> Task.succeed state)
spawnFailed callbacks error =
    case callbacks of
        SpawnCallbacksValue cb -> cb.onSpawnFailed error
        RunCallbacksValue cb -> cb.onSpawnFailed error

started callbacks operation info =
    case callbacks of
        SpawnCallbacksValue cb -> cb.onStarted operation info
        RunCallbacksValue cb -> cb.onStarted operation info

finishRejected router oid active detail state =
    let
        next =
            { state
                | active = Dict.remove oid state.active
                , stdinStates = Dict.remove oid state.stdinStates
            }
        remaining =
            Dict.foldl
                (\_ item count ->
                    if item.supervisor == active.supervisor then
                        count + 1
                    else
                        count
                )
                0
                next.active
        failed = spawnFailed active.callbacks (Child.SpawnFailed detail)
    in
    case Dict.get active.supervisor next.shutdowns of
        Just pendingShutdown ->
            if remaining == 0 then
                sendMany router
                    [ failed, pendingShutdown.callback (Ok { operationsFinished = pendingShutdown.total }) ]
                    { next | shutdowns = Dict.remove active.supervisor next.shutdowns }
            else
                send router failed next

        Nothing ->
            send router failed next


sendMany router messages state =
    messages
        |> List.map (Platform.sendToApp router)
        |> Task.sequence
        |> Task.andThen (\_ -> Task.succeed state)


finishOperation router oid active final state =
    let
        reason = final.cleanupReason

        pendingReadMessages =
            Dict.foldl
                (\rid pending acc ->
                    if pending.operation == oid then
                        pending.callback (Request pending.supervisor pending.operation rid) (Err (Child.ReadCancelled reason)) :: acc
                    else
                        acc
                )
                []
                state.reads

        pendingWriteMessages =
            Dict.foldl
                (\rid pending acc ->
                    if pending.operation == oid then
                        pending.callback (Request pending.supervisor pending.operation rid) (Err (Child.WriteCancelled reason)) :: acc
                    else
                        acc
                )
                []
                state.writes

        remainingReads = Dict.filter (\_ pending -> pending.operation /= oid) state.reads
        remainingWrites = Dict.filter (\_ pending -> pending.operation /= oid) state.writes
        next = { state | active = Dict.remove oid state.active, reads = remainingReads, writes = remainingWrites, stdinStates = Dict.remove oid state.stdinStates }
        operation = Operation active.supervisor oid
        finishedMsg =
            case active.callbacks of
                SpawnCallbacksValue cb -> cb.onFinished operation final
                RunCallbacksValue cb -> cb.onFinished operation (runResult final)
        remaining = Dict.foldl (\_ item count -> if item.supervisor == active.supervisor then count + 1 else count) 0 next.active
        terminalMessages =
            case Dict.get active.supervisor next.shutdowns of
                Just pendingShutdown ->
                    if remaining == 0 then
                        [ finishedMsg, pendingShutdown.callback (Ok { operationsFinished = pendingShutdown.total }) ]
                    else
                        [ finishedMsg ]

                Nothing ->
                    [ finishedMsg ]
        messages =
            List.concat [ pendingReadMessages, pendingWriteMessages, terminalMessages ]
        after = if remaining == 0 then { next | shutdowns = Dict.remove active.supervisor next.shutdowns } else next
    in
    sendMany router messages after

runResult final =
    let failure = { leader = Just final.leader, cleanup = final.cleanup, stdout = final.stdout, stderr = final.stderr } in
    case final.cleanupReason of
        Child.ExplicitCancel -> Err (Child.RunCancelled failure)
        Child.DeadlineReached -> Err (Child.RunDeadline failure)
        Child.OutputOverflowStdout -> Err (Child.RunOverflow failure)
        Child.OutputOverflowStderr -> Err (Child.RunOverflow failure)
        Child.InputTransportFailed -> Err (Child.RunInputError (transportWriteError final.transportDetail) failure)
        Child.ProcessTransportFailed -> Err (Child.RunTransportError (Maybe.withDefault "unknown process transport failure" final.transportDetail) failure)
        _ -> Ok final

transportWriteError detail =
    case detail of
        Just value -> mapWriteError value
        Nothing -> Child.WriteTransportFailed "unknown input transport failure"

mapCleanup detail ( termError, ( killError, ( parentReapFact, probeFacts ) ) ) =
    let
        signalResult error =
            if error == "" then Child.SignalSent else Child.SignalFailed error

        parentReapResult fact =
            if fact == "ack" then Child.ParentReapAcknowledged
            else if fact == "timeout" then Child.ParentReapTimedOut
            else if String.startsWith "failed:" fact then Child.ParentReapFailed (String.dropLeft 7 fact)
            else Child.ParentReapNotRequested

        probeResult fact =
            if fact == "gone" then Child.ProbeGone
            else if fact == "present" then Child.ProbePresent
            else if String.startsWith "failed:" fact then Child.ProbeFailed (String.dropLeft 7 fact)
            else Child.ProbeFailed fact

        evidence =
            { term = signalResult termError
            , kill = signalResult killError
            , parentReap = parentReapResult parentReapFact
            , probes = List.map probeResult probeFacts
            }
    in
    if detail == "gone" then
        Child.CleanupObservedGone evidence
    else
        Child.CleanupUncertain
            { term = evidence.term
            , kill = evidence.kill
            , parentReap = evidence.parentReap
            , probes = evidence.probes
            , detail = detail
            }

mapReason reason =
    case reason of
        "cancel" -> Child.ExplicitCancel
        "deadline" -> Child.DeadlineReached
        "shutdown" -> Child.SupervisorShutdown
        "input" -> Child.InputTransportFailed
        "transport" -> Child.ProcessTransportFailed
        "overflow-stdout" -> Child.OutputOverflowStdout
        "overflow-stderr" -> Child.OutputOverflowStderr
        _ -> Child.LeaderFinished

maybeCapture value =
    case value of
        Nothing -> Child.NotCaptured
        Just bytes -> Child.Captured bytes

mapReadError error =
    if String.startsWith "CANCELLED:" error then
        Child.ReadCancelled Child.ExplicitCancel
    else if error == "ALREADY_PENDING" then
        Child.ReadAlreadyPending
    else if error == "UNAVAILABLE" then
        Child.ReadUnavailable
    else
        Child.ReadTransportFailed error

mapWriteError error =
    if String.startsWith "BROKEN_PIPE:" error then
        Child.BrokenPipe
    else if String.startsWith "CANCELLED:" error then
        Child.WriteCancelled Child.ExplicitCancel
    else if error == "ALREADY_PENDING" then
        Child.WriteAlreadyPending
    else if error == "CLOSED" then
        Child.StdinAlreadyClosed
    else if error == "UNAVAILABLE" then
        Child.StdinUnavailable
    else
        Child.WriteTransportFailed error

mapSpawn error =
    case error of
        "ENOENT" -> Child.ExecutableNotFound
        "EACCES" -> Child.PermissionDenied
        _ -> Child.SpawnFailed error

onSelfMsg router self state =
    case self of
        BeginStart oid ->
            case Dict.get oid state.active of
                Just active ->
                    case active.phase of
                        Preparing ->
                            let
                                launch = active.launch
                                finish code signal reason detail cleanup evidence stdout stderr =
                                    Platform.sendToSelf router (Finished oid code signal reason detail cleanup evidence stdout stderr)
                                startTask =
                                    case launch.output of
                                        SpawnOutput stdout stderr ->
                                            Elm.Kernel.SchelmChildProcess.start finish oid launch.program launch.arguments launch.cwd launch.env launch.stdin ( stdout, ( stderr, ( launch.ipc, ( launch.grace, launch.deadline ) ) ) )
                                                |> Task.andThen (Spawned oid >> Platform.sendToSelf router)

                                        RunOutput stdout stderr ->
                                            Elm.Kernel.SchelmChildProcess.start finish oid launch.program launch.arguments launch.cwd launch.env launch.stdin ( stdout, ( stderr, ( launch.ipc, ( launch.grace, launch.deadline ) ) ) )
                                                |> Task.andThen (Spawned oid >> Platform.sendToSelf router)
                            in
                            Process.spawn startTask |> Task.andThen (\_ -> Task.succeed state)

                        _ ->
                            Task.succeed state

                Nothing ->
                    Task.succeed state

        Spawned oid result ->
            case Dict.get oid state.active of
                Nothing ->
                    Task.succeed state

                Just active ->
                    case ( active.phase, result ) of
                        ( Preparing, Err error ) ->
                            let
                                next =
                                    { state
                                        | active = Dict.remove oid state.active
                                        , stdinStates = Dict.remove oid state.stdinStates
                                    }
                            in
                            send router (spawnFailed active.callbacks (mapSpawn error)) next

                        ( Preparing, Ok pid ) ->
                            case active.parent of
                                Standalone ->
                                    let
                                        running = { active | phase = Running }
                                        next = { state | active = Dict.insert oid running state.active }
                                    in
                                    Platform.sendToSelf router (ExposeStarted oid pid pid)
                                        |> Task.andThen (\_ -> Task.succeed next)

                                Parented _ _ ->
                                    let
                                        binding = { active | phase = Binding pid }
                                        next = { state | active = Dict.insert oid binding state.active }
                                    in
                                    -- Binding is committed before BeginBind can launch the
                                    -- parent request. Its response returns only as ParentBound.
                                    Platform.sendToSelf router (BeginBind oid)
                                        |> Task.andThen (\_ -> Task.succeed next)

                        _ ->
                            Task.succeed state

        BeginBind oid ->
            case Dict.get oid state.active of
                Just active ->
                    case ( active.phase, active.parent ) of
                        ( Binding _, Parented reservation timeout ) ->
                            Elm.Kernel.SchelmChildProcess.parentBind oid reservation timeout
                                |> Task.map Ok
                                |> Task.onError (Err >> Task.succeed)
                                |> Task.andThen (ParentBound oid >> Platform.sendToSelf router)
                                |> Process.spawn
                                |> Task.andThen (\_ -> Task.succeed state)

                        _ ->
                            Task.succeed state

                Nothing ->
                    Task.succeed state

        ExposeStarted oid pid pgid ->
            case Dict.get oid state.active of
                Just active ->
                    case active.phase of
                        Running ->
                            let
                                demandOutput =
                                    case active.launch.output of
                                        SpawnOutput stdout stderr -> stdout == 2 || stderr == 2
                                        RunOutput _ _ -> False
                                afterStarted =
                                    if demandOutput then
                                        Elm.Kernel.SchelmChildProcess.arm oid
                                    else
                                        Platform.sendToSelf router (ArmOperation oid)
                            in
                            Platform.sendToApp router (started active.callbacks (Operation active.supervisor oid) { pid = pid, pgid = pgid })
                                |> Task.andThen (\_ -> afterStarted)
                                |> Task.andThen (\_ -> Task.succeed state)

                        _ ->
                            Task.succeed state

                Nothing ->
                    Task.succeed state

        ArmOperation oid ->
            case Dict.get oid state.active of
                Just active ->
                    case active.phase of
                        Running ->
                            Elm.Kernel.SchelmChildProcess.arm oid
                                |> Task.andThen (\_ -> Task.succeed state)

                        _ ->
                            Task.succeed state

                Nothing ->
                    Task.succeed state

        Finished oid code signal reason transportDetail cleanupDetail evidence stdout stderr ->
            case Dict.get oid state.active of
                Nothing ->
                    Task.succeed state

                Just active ->
                    case active.phase of
                        Rejecting detail ->
                            finishRejected router oid active detail state

                        _ ->
                            let
                                term = if signal /= "" then Child.Signaled signal else if code < 0 then Child.ExitUnknown else Child.Exited code
                                final = { leader = term, cleanupReason = mapReason reason, cleanup = mapCleanup cleanupDetail evidence, transportDetail = if transportDetail == "" then Nothing else Just transportDetail, stdout = maybeCapture stdout, stderr = maybeCapture stderr }
                            in
                            finishOperation router oid active final state

        ParentBound oid result ->
            case Dict.get oid state.active of
                Nothing ->
                    Task.succeed state

                Just active ->
                    case active.phase of
                        Binding _ ->
                            case result of
                                Ok ( pid, pgid ) ->
                                    let
                                        running = { active | phase = Running }
                                        next = { state | active = Dict.insert oid running state.active }
                                    in
                                    Platform.sendToSelf router (ExposeStarted oid pid pgid)
                                        |> Task.andThen (\_ -> Task.succeed next)

                                Err detail ->
                                    let
                                        rejecting = { active | phase = Rejecting detail }
                                        next = { state | active = Dict.insert oid rejecting state.active }
                                    in
                                    -- Failure notification is arbitrated by Finished: no
                                    -- onStarted and exactly one terminal spawn failure.
                                    Elm.Kernel.SchelmChildProcess.cancel oid
                                        |> Task.andThen (\_ -> Task.succeed next)

                        _ ->
                            Task.succeed state

        ReadDone rid result ->
            case Dict.get rid state.reads of
                Nothing -> Task.succeed state
                Just pending ->
                    let
                        mapped =
                            case result of
                                Err error -> Err (mapReadError error)
                                Ok Nothing -> Ok Child.End
                                Ok (Just bytes) -> Ok (Child.Chunk bytes)
                    in
                    send router (pending.callback (Request pending.supervisor pending.operation rid) mapped) { state | reads = Dict.remove rid state.reads }

        WriteDone rid result ->
            case Dict.get rid state.writes of
                Nothing -> Task.succeed state
                Just pending ->
                    let
                        mapped = Result.mapError mapWriteError result

                        stdinState =
                            case ( pending.kind, mapped ) of
                                ( Closing, Ok () ) -> StdinClosed
                                _ -> StdinIdle

                        next = { state | writes = Dict.remove rid state.writes, stdinStates = Dict.insert pending.operation stdinState state.stdinStates }
                    in
                    send router (pending.callback (Request pending.supervisor pending.operation rid) mapped) next
