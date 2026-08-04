port module Main exposing (main)
import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor
port report : Encode.Value -> Cmd msg
type alias Model = { supervisor : Maybe Supervisor.Supervisor }
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | SpawnFailed Child.SpawnError | Finished Supervisor.Operation Child.Final
main : Program () Model Msg
main = Platform.worker { init = \_ -> ( { supervisor = Nothing }, Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }
update msg model = case msg of
    Created (Err _) -> ( model, report (Encode.string "create-failed") )
    Created (Ok supervisor) ->
        case Child.program "/opt/elm-harness/current/runtime/node" of
            Err _ -> ( model, report (Encode.string "program-invalid") )
            Ok executable ->
                case Child.argument "-e" of
                    Err _ -> ( model, Cmd.none )
                    Ok a1 -> case Child.argument "process.exit(7)" of
                        Err _ -> ( model, Cmd.none )
                        Ok a2 -> ( { model | supervisor = Just supervisor }, Supervisor.spawn supervisor { onStarted = Started, onSpawnFailed = SpawnFailed, onFinished = Finished } executable [ a1, a2 ] Child.defaultSpawnOptions )
    Started _ info -> ( model, report (Encode.object [ ( "started", Encode.int info.pid ) ]) )
    SpawnFailed _ -> ( model, report (Encode.string "spawn-failed") )
    Finished _ final ->
        let
            cleanup =
                case final.cleanup of
                    Child.CleanupObservedGone _ -> "gone"
                    Child.CleanupUncertain evidence -> evidence.detail
            exitCode =
                case final.leader of
                    Child.Exited code -> code
                    _ -> -1
        in
        ( model, report (Encode.object [ ( "cleanup", Encode.string cleanup ), ( "exit", Encode.int exitCode ) ]) )
