port module ConformanceMain exposing (main)

import Bytes.Encode
import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor

port report : Encode.Value -> Cmd msg

type alias Model = { trace : List String, operation : Maybe Supervisor.Operation, finals : Int }
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | Failed Child.SpawnError | Read Supervisor.Request (Result Child.ReadError Child.ReadResult) | Wrote Supervisor.Request (Result Child.WriteError ()) | Finished Supervisor.Operation Child.Final

main : Program () Model Msg
main = Platform.worker { init = \_ -> ( { trace = List.reverse parentTrace, operation = Nothing, finals = 0 }, Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }

update msg model =
    case msg of
        Created (Err _) -> emit ("create-failed" :: model.trace) model
        Created (Ok supervisor) ->
            case ( Child.program "fake-program", Child.argument "arg" ) of
                ( Ok executable, Ok arg ) -> ( { model | trace = "created" :: model.trace }, Supervisor.spawn supervisor { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished } executable [ arg ] (Child.withSpawnStdin Child.StreamStdin Child.defaultSpawnOptions) )
                _ -> emit ("builder-failed" :: model.trace) model
        Started operation _ ->
            ( { model | trace = "started" :: model.trace, operation = Just operation }
            , Cmd.batch
                [ Supervisor.demandStdout operation Read
                , Supervisor.writeStdin operation (Bytes.Encode.encode (Bytes.Encode.unsignedInt8 1)) Wrote
                ]
            )
        Failed _ -> emit ("spawn-failed" :: model.trace) model
        Read _ result ->
            let
                label =
                    case result of
                        Err (Child.ReadCancelled _) -> "read-cancelled"
                        Err _ -> "read-error"
                        Ok _ -> "read-ok"
            in
            ( { model | trace = label :: model.trace }, Cmd.none )
        Wrote _ result ->
            let
                label =
                    case result of
                        Err (Child.WriteCancelled _) -> "write-cancelled"
                        Err Child.BrokenPipe -> "write-broken"
                        Err _ -> "write-error"
                        Ok _ -> "write-ok"
            in
            ( { model | trace = label :: model.trace }, Cmd.none )
        Finished _ final ->
            let
                cleanup =
                    case final.cleanup of
                        Child.CleanupObservedGone evidence -> "gone:" ++ String.fromInt (List.length evidence.probes)
                        Child.CleanupUncertain evidence -> "uncertain:" ++ evidence.detail
            in
            emit (("final:" ++ reason final.cleanupReason ++ ":" ++ cleanup) :: model.trace) model

emit reversed model = ( model, report (Encode.list Encode.string (List.reverse reversed)) )
reason value =
    case value of
        Child.ExplicitCancel -> "cancel"
        Child.DeadlineReached -> "deadline"
        Child.SupervisorShutdown -> "shutdown"
        Child.OutputOverflowStdout -> "overflow-out"
        Child.OutputOverflowStderr -> "overflow-err"
        Child.InputTransportFailed -> "input"
        Child.ProcessTransportFailed -> "transport"
        Child.LeaderFinished -> "leader"

parentTrace =
    [ "parent:none", "parent:bind", "parent:none", "parent:start", "parent:unregister", "parent:final" ]
