port module RunMain exposing (main)
import Bytes
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor
port report : String -> Cmd msg
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | Failed Child.SpawnError | Finished Supervisor.Operation (Result Child.RunError Child.Final)
main : Program () () Msg
main = Platform.worker { init = \_ -> ( (), Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }
update msg model =
    case msg of
        Created (Err _) -> ( model, report "create-failed" )
        Created (Ok supervisor) ->
            case ( Child.program "/opt/elm-harness/current/runtime/node", Child.argument "-e", Child.argument "process.stdout.write('CAP');process.exit(9)" ) of
                ( Ok executable, Ok a1, Ok a2 ) -> ( model, Supervisor.run supervisor { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished } executable [ a1, a2 ] Child.defaultRunOptions )
                _ -> ( model, report "builder-failed" )
        Started _ _ -> ( model, Cmd.none )
        Failed _ -> ( model, report "spawn-failed" )
        Finished _ result ->
            case result of
                Err _ -> ( model, report "run-failed" )
                Ok final ->
                    case ( final.leader, final.stdout ) of
                        ( Child.Exited 9, Child.Captured bytes ) -> ( model, report (if Bytes.width bytes == 3 then "ok" else "bad-width") )
                        _ -> ( model, report "bad-result" )
