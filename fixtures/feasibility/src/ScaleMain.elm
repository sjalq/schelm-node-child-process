port module ScaleMain exposing (main)
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor
port report : String -> Cmd msg
type alias Model = { started : Int, finished : Int, supervisor : Maybe Supervisor.Supervisor }
type Msg = Created (Result Child.CreateError Supervisor.Supervisor) | Started Supervisor.Operation Child.ProcessInfo | Failed Child.SpawnError | Finished Supervisor.Operation (Result Child.RunError Child.Final)
main : Program () Model Msg
main = Platform.worker { init = \_ -> ( { started = 0, finished = 0, supervisor = Nothing }, Supervisor.create Created ), update = update, subscriptions = \_ -> Sub.none }
update msg model = case msg of
    Created (Err _) -> ( model, report "create-failed" )
    Created (Ok supervisor) -> ( { model | supervisor = Just supervisor }, startRun supervisor )
    Started _ _ -> ( { model | started = model.started + 1 }, Cmd.none )
    Failed _ -> ( model, report "spawn-failed" )
    Finished _ result -> case result of
        Err _ -> ( model, report "run-failed" )
        Ok _ -> let next = { model | finished = model.finished + 1 } in
            if next.finished == 200 then ( next, report (if next.started == 200 then "ok" else "bad-count") )
            else case next.supervisor of
                Nothing -> ( next, report "missing-supervisor" )
                Just supervisor -> ( next, startRun supervisor )
startRun supervisor = case ( Child.program "/opt/elm-harness/current/runtime/node", Child.argument "-e", Child.argument "process.exit(0)" ) of
    ( Ok executable, Ok a1, Ok a2 ) -> Supervisor.run supervisor { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished } executable [ a1, a2 ] Child.defaultRunOptions
    _ -> report "builder-failed"
