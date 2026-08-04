port module ParentedMain exposing (main)

import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.ParentAdapter as Parent
import Schelm.Node.ChildProcess.Supervisor as Supervisor

port report : Encode.Value -> Cmd msg

type alias Model = ()
type Msg
    = Prepared (Result Parent.PrepareError Parent.Prepared)
    | Created (Result Child.CreateError Supervisor.Supervisor)
    | Started Supervisor.Operation Child.ProcessInfo
    | Failed Child.SpawnError
    | Finished Supervisor.Operation Child.Final

main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( (), Parent.prepare Parent.defaultOptions Prepared )
        , update = update
        , subscriptions = \_ -> Sub.none
        }

update msg model =
    case msg of
        Prepared (Err _) -> ( model, report (Encode.string "prepare-failed") )
        Prepared (Ok prepared) -> ( model, Supervisor.createParented prepared Created )
        Created (Err _) -> ( model, report (Encode.string "create-failed") )
        Created (Ok supervisor) ->
            case ( Child.program "/opt/elm-harness/current/runtime/node", Child.argument "-e", Child.argument "process.on('SIGTERM',()=>{});setTimeout(()=>process.exit(0),25)" ) of
                ( Ok executable, Ok a1, Ok a2 ) ->
                    ( model
                    , Supervisor.spawn supervisor
                        { onStarted = Started, onSpawnFailed = Failed, onFinished = Finished }
                        executable [ a1, a2 ] Child.defaultSpawnOptions
                    )
                _ -> ( model, report (Encode.string "builder-failed") )
        Started _ info ->
            ( model, report (Encode.object [ ( "started", Encode.int info.pid ), ( "pgid", Encode.int info.pgid ) ]) )
        Failed (Child.SpawnFailed "cancelled") -> ( model, Cmd.none )
        Failed _ -> ( model, report (Encode.string "spawn-failed") )
        Finished _ final ->
            let
                reap =
                    case final.cleanup of
                        Child.CleanupObservedGone evidence -> parentReap evidence.parentReap
                        Child.CleanupUncertain evidence -> parentReap evidence.parentReap
            in
            ( model, report (Encode.object [ ( "finished", Encode.string reap ) ]) )

parentReap evidence =
    case evidence of
        Child.ParentReapNotRequested -> "not-requested"
        Child.ParentReapAcknowledged -> "ack"
        Child.ParentReapTimedOut -> "timeout"
        Child.ParentReapFailed detail -> "failed:" ++ detail
