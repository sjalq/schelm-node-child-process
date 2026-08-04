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

type alias Active msg = { supervisor : Int, callbacks : Callbacks msg }
type alias PendingRead msg = { supervisor : Int, operation : Int, callback : Request -> Result Child.ReadError Child.ReadResult -> msg }
type WriteKind = Writing | Closing

type StdinState = StdinIdle | StdinBusy WriteKind | StdinClosed

type alias PendingWrite msg = { supervisor : Int, operation : Int, kind : WriteKind, callback : Request -> Result Child.WriteError () -> msg }
type alias State msg =
    { nextSupervisor : Int, nextOperation : Int, nextRequest : Int
    , supervisors : Dict Int (Maybe ( Int, Int )), active : Dict Int (Active msg)
    , shutdowns : Dict Int (Result Child.ControlError Child.ShutdownReport -> msg)
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
    = Finished Int Int String String String String ( String, ( String, List String ) ) (Maybe Bytes) (Maybe Bytes)
    | ParentBound Int Int Int (Result String ( Int, Int ))
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
                send router (cb (Ok (Supervisor sid))) { state | nextSupervisor = sid + 1, supervisors = Dict.insert sid Nothing state.supervisors }

        CreateParented prepared cb ->
            if state.nextSupervisor >= maxId then
                send router (cb (Err (Child.IdentifierExhausted Child.SupervisorIdentifier))) state
            else if not Elm.Kernel.SchelmChildProcess.isUnix then
                send router (cb (Err Child.UnsupportedPlatform)) state
            else
                let
                    sid = state.nextSupervisor
                    reservation = ParentAdapter.reservation prepared
                    parent = ( reservation, ParentAdapter.responseTimeout prepared )
                in
                Elm.Kernel.SchelmChildProcess.parentClaim reservation
                    |> Task.andThen
                        (\claimed ->
                            if claimed then
                                send router (cb (Ok (Supervisor sid))) { state | nextSupervisor = sid + 1, supervisors = Dict.insert sid (Just parent) state.supervisors }
                            else
                                send router (cb (Err (Child.UnsupportedRuntime "parent reservation already consumed"))) state
                        )

        Spawn (Supervisor sid) cb executable arguments options ->
            start router sid (SpawnCallbacksValue cb) executable arguments (Child.spawnFacts options) state

        Run (Supervisor sid) cb executable arguments options ->
            start router sid (RunCallbacksValue cb) executable arguments (Child.runFacts options) state

        Demand stdout (Operation sid oid) cb ->
            startRead router stdout sid oid cb state

        Write (Operation sid oid) bytes cb ->
            startWrite router sid oid bytes cb state

        Close (Operation sid oid) cb ->
            startClose router sid oid cb state

        Cancel (Operation sid oid) cb ->
            if owned sid oid state then
                Elm.Kernel.SchelmChildProcess.cancel oid |> Task.andThen (\_ -> send router (cb (Ok ())) state)
            else
                send router (cb (Err Child.UnknownOperation)) state

        Shutdown (Supervisor sid) cb ->
            if Dict.member sid state.supervisors then
                let ids = Dict.foldl (\oid active acc -> if active.supervisor == sid then oid :: acc else acc) [] state.active in
                if List.isEmpty ids then
                    send router (cb (Ok { operationsFinished = 0 })) { state | supervisors = Dict.remove sid state.supervisors }
                else
                    Elm.Kernel.SchelmChildProcess.cancelMany ids
                        |> Task.andThen (\_ -> Task.succeed { state | supervisors = Dict.remove sid state.supervisors, shutdowns = Dict.insert sid cb state.shutdowns })
            else
                send router (cb (Err Child.UnknownOperation)) state

start router sid cb executable arguments facts state =
    if not (Dict.member sid state.supervisors) then
        send router (spawnFailed cb (Child.SpawnFailed "unknown supervisor")) state
    else if state.nextOperation >= maxId then
        send router (spawnFailed cb (Child.IdentifierExhaustedOnSpawn Child.OperationIdentifier)) state
    else
        let
            oid = state.nextOperation
            finish code signal reason detail cleanup evidence stdout stderr = Platform.sendToSelf router (Finished oid code signal reason detail cleanup evidence stdout stderr)
        in
        Elm.Kernel.SchelmChildProcess.start finish oid (Child.programString executable) (Child.argumentsStrings arguments) facts.cwd facts.env facts.stdin ( facts.stdout, ( facts.stderr, ( facts.grace, facts.deadline ) ) )
            |> Task.andThen
                (\result ->
                    case result of
                        Err error -> send router (spawnFailed cb (mapSpawn error)) { state | nextOperation = oid + 1 }
                        Ok pid ->
                            let
                                next = { state | nextOperation = oid + 1, active = Dict.insert oid { supervisor = sid, callbacks = cb } state.active, stdinStates = Dict.insert oid StdinIdle state.stdinStates }
                                arm = Process.sleep 0 |> Task.andThen (\_ -> Elm.Kernel.SchelmChildProcess.arm oid)
                                expose info = Process.spawn arm |> Task.andThen (\_ -> send router (started cb (Operation sid oid) info) next)
                            in
                            case Dict.get sid state.supervisors |> Maybe.andThen identity of
                                Nothing -> expose { pid = pid, pgid = pid }
                                Just ( reservation, timeout ) ->
                                    Elm.Kernel.SchelmChildProcess.parentBind oid reservation timeout
                                        |> Task.map Ok
                                        |> Task.onError (Err >> Task.succeed)
                                        |> Task.andThen
                                            (\bindResult ->
                                                Process.sleep 0
                                                    |> Task.andThen (\_ -> Platform.sendToSelf router (ParentBound sid oid pid bindResult))
                                            )
                                        |> Process.spawn
                                        |> Task.andThen (\_ -> Task.succeed next)
                )

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
        messages =
            case Dict.get active.supervisor next.shutdowns of
                Just shutdownCb ->
                    if remaining == 0 then pendingReadMessages ++ pendingWriteMessages ++ [ finishedMsg, shutdownCb (Ok { operationsFinished = 0 }) ] else pendingReadMessages ++ pendingWriteMessages ++ [ finishedMsg ]
                Nothing -> pendingReadMessages ++ pendingWriteMessages ++ [ finishedMsg ]
        after = if remaining == 0 then { next | shutdowns = Dict.remove active.supervisor next.shutdowns } else next
        notify = Process.sleep 0 |> Task.andThen (\_ -> messages |> List.map (Platform.sendToApp router) |> Task.sequence |> Task.map (always ()))
    in
    Process.spawn notify |> Task.andThen (\_ -> Task.succeed after)

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

mapCleanup detail ( termError, ( killError, probeFacts ) ) =
    let
        signalResult error =
            if error == "" then Child.SignalSent else Child.SignalFailed error

        probeResult fact =
            if fact == "gone" then Child.ProbeGone
            else if fact == "present" then Child.ProbePresent
            else if String.startsWith "failed:" fact then Child.ProbeFailed (String.dropLeft 7 fact)
            else Child.ProbeFailed fact

        evidence =
            { term = signalResult termError
            , kill = signalResult killError
            , probes = List.map probeResult probeFacts
            }
    in
    if detail == "gone" then
        Child.CleanupObservedGone evidence
    else
        Child.CleanupUncertain
            { term = evidence.term
            , kill = evidence.kill
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
        Finished oid code signal reason transportDetail cleanupDetail evidence stdout stderr ->
            case Dict.get oid state.active of
                Nothing -> Task.succeed state
                Just active ->
                    let
                        term = if signal /= "" then Child.Signaled signal else if code < 0 then Child.ExitUnknown else Child.Exited code
                        final = { leader = term, cleanupReason = mapReason reason, cleanup = mapCleanup cleanupDetail evidence, transportDetail = if transportDetail == "" then Nothing else Just transportDetail, stdout = maybeCapture stdout, stderr = maybeCapture stderr }
                    in
                    finishOperation router oid active final state

        ParentBound sid oid _ result ->
            case Dict.get oid state.active of
                Nothing -> Task.succeed state
                Just active ->
                    case result of
                        Ok ( pid, pgid ) ->
                            let
                                operation = Operation sid oid
                                arm = Process.sleep 0 |> Task.andThen (\_ -> Elm.Kernel.SchelmChildProcess.arm oid)
                            in
                            Process.spawn arm |> Task.andThen (\_ -> send router (started active.callbacks operation { pid = pid, pgid = pgid }) state)
                        Err detail ->
                            Elm.Kernel.SchelmChildProcess.cancel oid
                                |> Task.andThen (\_ -> send router (spawnFailed active.callbacks (Child.SpawnFailed detail)) state)

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
