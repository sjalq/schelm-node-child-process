port module DemandMain exposing (main)

import Bytes
import Json.Encode as Encode
import Platform
import Schelm.Node.ChildProcess as Child
import Schelm.Node.ChildProcess.Supervisor as Supervisor

port report : Encode.Value -> Cmd msg

type alias Model =
    { operation : Maybe Supervisor.Operation
    , bytes : Int
    , chunks : Int
    , ended : Bool
    , finished : Bool
    }

type Msg
    = Created (Result Child.CreateError Supervisor.Supervisor)
    | Started Supervisor.Operation Child.ProcessInfo
    | SpawnFailed Child.SpawnError
    | Read Supervisor.Request (Result Child.ReadError Child.ReadResult)
    | Finished Supervisor.Operation Child.Final

main : Program () Model Msg
main =
    Platform.worker
        { init = \_ -> ( { operation = Nothing, bytes = 0, chunks = 0, ended = False, finished = False }, Supervisor.create Created )
        , update = update
        , subscriptions = \_ -> Sub.none
        }

update msg model =
    case msg of
        Created (Err _) -> ( model, report (Encode.string "create-failed") )
        Created (Ok supervisor) ->
            case ( Child.program "/opt/elm-harness/current/runtime/node", Child.argument "-e", Child.argument producer ) of
                ( Ok executable, Ok a1, Ok a2 ) ->
                    ( model, Supervisor.spawn supervisor { onStarted = Started, onSpawnFailed = SpawnFailed, onFinished = Finished } executable [ a1, a2 ] Child.defaultSpawnOptions )
                _ -> ( model, report (Encode.string "builder-failed") )
        Started operation _ -> ( { model | operation = Just operation }, Supervisor.demandStdout operation Read )
        SpawnFailed _ -> ( model, report (Encode.string "spawn-failed") )
        Read _ (Err error) -> ( model, report (Encode.string (readError error)) )
        Read _ (Ok Child.End) -> complete { model | ended = True }
        Read _ (Ok (Child.Chunk bytes)) ->
            let next = { model | bytes = model.bytes + Bytes.width bytes, chunks = model.chunks + 1 } in
            case next.operation of
                Nothing -> ( next, report (Encode.string "missing-operation") )
                Just operation -> ( next, Supervisor.demandStdout operation Read )
        Finished _ _ -> complete { model | finished = True }

complete model =
    if model.ended && model.finished then
        ( model, report (Encode.object [ ( "bytes", Encode.int model.bytes ), ( "chunks", Encode.int model.chunks ) ]) )
    else
        ( model, Cmd.none )

readError error =
    case error of
        Child.ReadCancelled _ -> "read-cancelled"
        Child.ReadUnknownOperation -> "read-unknown"
        Child.ReadUnavailable -> "read-unavailable"
        Child.ReadAlreadyPending -> "read-pending"
        Child.ReadTransportFailed detail -> "read-transport:" ++ detail

producer =
    "const b=Buffer.alloc(1024,120);let i=0;function go(){while(i<10000){i++;if(!process.stdout.write(b))return process.stdout.once('drain',go)}process.stdout.end()}go()"
