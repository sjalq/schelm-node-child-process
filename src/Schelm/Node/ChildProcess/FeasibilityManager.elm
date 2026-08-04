effect module Schelm.Node.ChildProcess.FeasibilityManager where { command = MyCmd } exposing (Operation, Callbacks, spawn)

{-| Feasibility-only proof that an installed authorized `sjalq/*` package may
own an effect manager. This is not the v1 API.

@docs Operation, Callbacks, spawn
-}

import Dict exposing (Dict)
import Platform
import Platform.Cmd exposing (Cmd)
import Process as ElmProcess
import Schelm.Node.ChildProcess.Feasibility as Child
import Task exposing (Task)


{-| Opaque manager-minted operation. -}
type Operation
    = Operation Int


{-| Lifecycle callbacks for the proof. -}
type alias Callbacks msg =
    { onStarted : Operation -> msg
    , onSpawnFailed : String -> msg
    , onExited : Operation -> Child.Exit -> msg
    }


{-| Ask the manager to spawn and own a process. -}
spawn : Callbacks msg -> String -> List String -> Cmd msg
spawn callbacks program arguments =
    command (Spawn callbacks program arguments)


type MyCmd msg
    = Spawn (Callbacks msg) String (List String)


cmdMap : (a -> b) -> MyCmd a -> MyCmd b
cmdMap mapper command_ =
    case command_ of
        Spawn callbacks program arguments ->
            Spawn
                { onStarted = callbacks.onStarted >> mapper
                , onSpawnFailed = callbacks.onSpawnFailed >> mapper
                , onExited = \operation exit -> mapper (callbacks.onExited operation exit)
                }
                program
                arguments


type alias Active msg =
    { process : Child.Process
    , callbacks : Callbacks msg
    }


type alias State msg =
    { next : Int
    , active : Dict Int (Active msg)
    }


type SelfMsg
    = ProcessExited Int Child.Exit


type alias MyRouter msg =
    Platform.Router msg SelfMsg


init : Task Never (State msg)
init =
    Task.succeed { next = 0, active = Dict.empty }


onEffects : MyRouter msg -> List (MyCmd msg) -> State msg -> Task Never (State msg)
onEffects router commands state =
    applyCommands router commands state


applyCommands : MyRouter msg -> List (MyCmd msg) -> State msg -> Task Never (State msg)
applyCommands router commands state =
    case commands of
        [] ->
            Task.succeed state

        command_ :: rest ->
            applyCommand router command_ state
                |> Task.andThen (applyCommands router rest)


applyCommand : MyRouter msg -> MyCmd msg -> State msg -> Task Never (State msg)
applyCommand router command_ state =
    case command_ of
        Spawn callbacks program arguments ->
            Child.spawn program arguments
                |> Task.map Ok
                |> Task.onError (Err >> Task.succeed)
                |> Task.andThen
                    (\result ->
                        case result of
                            Err error ->
                                Platform.sendToApp router (callbacks.onSpawnFailed error)
                                    |> Task.andThen (\_ -> Task.succeed { state | next = state.next + 1 })

                            Ok process ->
                                let
                                    operation =
                                        Operation state.next

                                    waiter =
                                        Child.wait process
                                            |> Task.andThen (ProcessExited state.next >> Platform.sendToSelf router)

                                    next =
                                        { next = state.next + 1
                                        , active = Dict.insert state.next { process = process, callbacks = callbacks } state.active
                                        }
                                in
                                ElmProcess.spawn waiter
                                    |> Task.andThen
                                        (\_ ->
                                            Platform.sendToApp router (callbacks.onStarted operation)
                                                |> Task.andThen (\_ -> Task.succeed next)
                                        )
                    )


onSelfMsg : MyRouter msg -> SelfMsg -> State msg -> Task Never (State msg)
onSelfMsg router (ProcessExited operationId exit) state =
    case Dict.get operationId state.active of
        Nothing ->
            Task.succeed state

        Just active ->
            Platform.sendToApp router (active.callbacks.onExited (Operation operationId) exit)
                |> Task.andThen (\_ -> Task.succeed { state | active = Dict.remove operationId state.active })
