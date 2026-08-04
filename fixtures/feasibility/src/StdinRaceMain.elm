port module StdinRaceMain exposing (main)

import Bytes.Encode
import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor

port report : Encode.Value -> Cmd msg

type alias Model = { trace : List String, operation : Maybe Supervisor.Operation }
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | Failed Child.SpawnError | Wrote Supervisor.Request (Result Child.WriteError ()) | Closed Supervisor.Request (Result Child.WriteError ()) | Finished Supervisor.Operation Child.Final

main : Program () Model Msg
main = Platform.worker { init = \_ -> ( { trace = [], operation = Nothing }, Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }

update msg model =
    case msg of
        Created (Err _) -> emit [ "create-failed" ] model
        Created (Ok supervisor) ->
            case ( Child.program "fake-program", Child.argument "arg" ) of
                ( Ok executable, Ok arg ) -> ( model, Supervisor.spawn supervisor { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished } executable [ arg ] (Child.withSpawnStdin Child.StreamStdin Child.defaultSpawnOptions) )
                _ -> emit [ "builder-failed" ] model
        Started operation _ ->
            ( { model | operation = Just operation }
            , Cmd.batch
                [ Supervisor.closeStdin operation Closed
                , Supervisor.writeStdin operation (Bytes.Encode.encode (Bytes.Encode.unsignedInt8 1)) Wrote
                ]
            )
        Failed (Child.SpawnFailed "cancelled") -> ( model, Cmd.none )
        Failed _ -> emit [ "spawn-failed" ] model
        Wrote _ result ->
            let next = { model | trace = writeLabel "write" result :: model.trace } in
            case ( result, next.operation ) of
                ( Ok (), Just operation ) -> ( next, Supervisor.closeStdin operation Closed )
                ( Err Child.BrokenPipe, Just operation ) -> ( next, Supervisor.cancel operation (\_ -> Failed (Child.SpawnFailed "cancelled")) )
                _ -> ( next, Cmd.none )
        Closed _ result ->
            let next = { model | trace = writeLabel "close" result :: model.trace } in
            case ( result, next.operation ) of
                ( Err Child.WriteAlreadyPending, _ ) -> ( next, Cmd.none )
                ( Ok (), Just operation ) -> ( next, Supervisor.closeStdin operation Closed )
                ( Err Child.StdinAlreadyClosed, Just operation ) -> ( next, Supervisor.cancel operation (\_ -> Failed (Child.SpawnFailed "cancelled")) )
                _ -> ( next, Cmd.none )
        Finished _ _ -> emit ("final" :: model.trace) model

writeLabel prefix result =
    case result of
        Ok () -> prefix ++ ":ok"
        Err Child.WriteAlreadyPending -> prefix ++ ":busy"
        Err Child.StdinAlreadyClosed -> prefix ++ ":closed"
        Err Child.BrokenPipe -> prefix ++ ":broken"
        Err (Child.WriteCancelled _) -> prefix ++ ":cancelled"
        Err _ -> prefix ++ ":other"

emit reversed model = ( model, report (Encode.list Encode.string (List.reverse reversed)) )
