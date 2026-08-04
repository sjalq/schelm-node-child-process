module Schelm.Node.ChildProcess.ParentAdapter exposing
    ( Prepared
    , Options
    , PrepareError(..)
    , defaultOptions
    , withResponseTimeout
    , prepare
    , reservation
    , responseTimeout
    )

{-| Parent-process reservation transport.

`prepare` sends a `schelm-child.prepare` request over Node IPC and produces an
opaque, single-use capability only after the parent acknowledges it. The
capability contains no PID, PGID, or signalling authority.

@docs Prepared, Options, PrepareError, defaultOptions, withResponseTimeout, prepare
@docs reservation, responseTimeout
-}

import Elm.Kernel.SchelmChildProcess
import Platform.Cmd exposing (Cmd)
import Task


{-| Parent-acknowledged reservation. -}
type Prepared
    = Prepared Int Int


{-| Validated parent response timeout. -}
type Options
    = Options Int


{-| Reservation failure before any physical child exists. -}
type PrepareError
    = ParentUnavailable
    | ParentRejected String
    | ParentTransportLost
    | ParentResponseTimedOut
    | ReservationExhausted


{-| Five-second response bound. -}
defaultOptions : Options
defaultOptions =
    Options 5000


{-| Set a positive, safe response bound. -}
withResponseTimeout : Int -> Options -> Maybe Options
withResponseTimeout milliseconds _ =
    if milliseconds > 0 && milliseconds <= 9007199254740990 then
        Just (Options milliseconds)
    else
        Nothing


{-| Reserve with the parent before spawn. -}
prepare : Options -> (Result PrepareError Prepared -> msg) -> Cmd msg
prepare (Options timeout) callback =
    Elm.Kernel.SchelmChildProcess.parentPrepare timeout
        |> Task.map (mapPrepare timeout)
        |> Task.onError (mapError >> Err >> Task.succeed)
        |> Task.perform callback


mapPrepare : Int -> Int -> Result PrepareError Prepared
mapPrepare timeout reservationId =
    Ok (Prepared reservationId timeout)


mapError : String -> PrepareError
mapError detail =
    if detail == "PARENT_UNAVAILABLE" then
        ParentUnavailable
    else if detail == "PARENT_TRANSPORT_LOST" then
        ParentTransportLost
    else if detail == "PARENT_TIMEOUT" then
        ParentResponseTimedOut
    else if detail == "RESERVATION_EXHAUSTED" then
        ReservationExhausted
    else
        ParentRejected detail


{-| Package integration accessor; reservation identity is not process authority. -}
reservation : Prepared -> Int
reservation (Prepared value _) =
    value


{-| Package integration accessor. -}
responseTimeout : Prepared -> Int
responseTimeout (Prepared _ value) =
    value
