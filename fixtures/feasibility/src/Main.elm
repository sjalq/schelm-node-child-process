port module Main exposing (main)
import Bytes exposing (Bytes)
import Json.Encode as Encode
import Platform
import Process
import Schelm.Node.ChildProcess.Feasibility as Child
import Task
port report : Encode.Value -> Cmd msg
type alias Model = ()
type Msg = Start (Result String Child.Process) | Out Child.Process (Result String (Maybe Bytes)) | ErrorChunk Child.Process (Result String (Maybe Bytes)) | Done Child.Exit | Missing (Result String Child.Process) | Long (Result String Child.Process)
main : Program () Model Msg
main = Platform.worker { init = \_ -> ( (), Cmd.batch [ Task.attempt Start (Child.spawn "/opt/elm-harness/current/runtime/node" [ "-e", "process.stdout.write('OUT');process.stderr.write('ERR');setTimeout(()=>process.exit(7),20)" ]), Task.attempt Missing (Child.spawn "/definitely/missing-schelm-command" []), Task.attempt Long (Child.spawn "/opt/elm-harness/current/runtime/node" [ "-e", "process.on('SIGTERM',()=>process.exit(0));setInterval(()=>{},1000)" ]) ] ), update = update, subscriptions = \_ -> Sub.none }
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model = case msg of
    Start (Err error) -> ( model, report (Encode.string ("unexpected:" ++ error)) )
    Start (Ok child) -> ( model, Cmd.batch [ Task.attempt (Out child) (Child.readStdout child), Task.attempt (ErrorChunk child) (Child.readStderr child), Task.perform Done (Child.wait child) ] )
    Out _ result -> ( model, report (Encode.string (chunk "stdout" result)) )
    ErrorChunk _ result -> ( model, report (Encode.string (chunk "stderr" result)) )
    Done status -> ( model, report (Encode.object [ ( "exit", Encode.int status.code ), ( "signal", Encode.string status.signal ) ]) )
    Missing result -> ( model, report (Encode.string (case result of
            Err e -> "spawn-failed:" ++ e
            Ok _ -> "unexpected-spawn")) )
    Long result -> case result of
        Err e -> ( model, report (Encode.string ("unexpected:" ++ e)) )
        Ok child -> ( model, Task.perform Done (Child.terminate child |> Task.andThen (\_ -> Child.wait child)) )
chunk : String -> Result String (Maybe Bytes) -> String
chunk name result = case result of
        Err e -> name ++ "-error:" ++ e
        Ok Nothing -> name ++ "-end"
        Ok (Just bytes) -> name ++ ":" ++ String.fromInt (Bytes.width bytes)
