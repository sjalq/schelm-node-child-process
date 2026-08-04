port module RunFailureMain exposing (main)

import Bytes.Encode
import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor

port report : Encode.Value -> Cmd msg

type alias Flags = { mode : String }
type alias Model = { mode : String }
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | Failed Child.SpawnError | Finished Supervisor.Operation (Result Child.RunError Child.Final)

main : Program Flags Model Msg
main = Platform.worker { init = \flags -> ( { mode = flags.mode }, Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }

update msg model =
    case msg of
        Created (Err _) -> ( model, report (Encode.string "create-failed") )
        Created (Ok supervisor) ->
            case ( Child.program "fake-program", Child.argument "arg" ) of
                ( Ok executable, Ok arg ) ->
                    let
                        options =
                            if model.mode == "input" then
                                Child.withRunStdin (Child.RunInputBytes (Bytes.Encode.encode (Bytes.Encode.unsignedInt8 1))) Child.defaultRunOptions
                            else
                                Child.defaultRunOptions
                    in
                    ( model, Supervisor.run supervisor { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished } executable [ arg ] options )
                _ -> ( model, report (Encode.string "builder-failed") )
        Started _ _ -> ( model, Cmd.none )
        Failed _ -> ( model, report (Encode.string "spawn-failed") )
        Finished _ result -> ( model, report (encodeResult result) )

encodeResult result =
    case result of
        Err (Child.RunInputError error _) ->
            Encode.object [ ( "kind", Encode.string "input" ), ( "detail", Encode.string (writeDetail error) ) ]
        Err (Child.RunTransportError detail _) ->
            Encode.object [ ( "kind", Encode.string "process" ), ( "detail", Encode.string detail ) ]
        Err _ -> Encode.object [ ( "kind", Encode.string "other" ) ]
        Ok _ -> Encode.object [ ( "kind", Encode.string "ok" ) ]

writeDetail error =
    case error of
        Child.BrokenPipe -> "broken-pipe"
        Child.WriteTransportFailed detail -> detail
        Child.WriteCancelled _ -> "cancelled"
        Child.WriteUnknownOperation -> "unknown"
        Child.StdinUnavailable -> "unavailable"
        Child.WriteAlreadyPending -> "busy"
        Child.StdinAlreadyClosed -> "closed"
