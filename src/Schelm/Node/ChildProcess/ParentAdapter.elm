module Schelm.Node.ChildProcess.ParentAdapter exposing
    ( Slot, Facts, State(..), Error(..), Action(..), Event(..)
    , prepared, initial, step
    )

{-| Pure protocol for an external watchdog. Transport is supplied by a later integration.
@docs Slot, Facts, State, Error, Action, Event, prepared, initial, step
-}

{-| Parent-minted slot identity. -}
type Slot = Slot Int

{-| Bound leader/process-group facts. -}
type alias Facts = { pid : Int, pgid : Int }

{-| Registration lifecycle; preparation necessarily precedes binding/spawn acknowledgement. -}
type State
    = Absent
    | Prepared Slot
    | Binding Slot Facts
    | BoundAwaitingAck Slot Facts
    | Registered Slot Facts
    | Unregistering Slot Facts

{-| Fail-closed protocol error. -}
type Error = UnexpectedEvent | SlotMismatch

{-| Verb requested from transport. -}
type Action = NoAction | SendBind Slot Facts | PermitStarted | KillAndClear Slot Facts | SendUnregister Slot | PermitFinal

{-| Fact entering the pure protocol. -}
type Event
    = PrepareSucceeded Slot
    | BindRequested Slot Facts
    | BindSent
    | RegistrationAcknowledged Slot
    | RegistrationFailed Slot
    | RegistrationTimedOut Slot
    | CleanupCompleted Slot
    | UnregisterAcknowledged Slot
    | UnregisterTimedOut Slot

{-| Construct a parent-minted slot. The parent must never reuse it in one runtime. -}
prepared : Int -> Slot
prepared = Slot

{-| No parent registration exists initially. -}
initial : State
initial = Absent

{-| Total deterministic registration transition. Failure/timeout after bind requests kill-and-clear. -}
step : Event -> State -> Result Error ( State, Action )
step event state =
    case ( state, event ) of
        ( Absent, PrepareSucceeded slot ) -> Ok ( Prepared slot, NoAction )
        ( Prepared slot, BindRequested requested facts ) -> if slot == requested then Ok ( Binding slot facts, SendBind slot facts ) else Err SlotMismatch
        ( Binding slot facts, BindSent ) -> Ok ( BoundAwaitingAck slot facts, NoAction )
        ( BoundAwaitingAck slot facts, RegistrationAcknowledged acknowledged ) -> if slot == acknowledged then Ok ( Registered slot facts, PermitStarted ) else Err SlotMismatch
        ( BoundAwaitingAck slot facts, RegistrationFailed failed ) -> if slot == failed then Ok ( Absent, KillAndClear slot facts ) else Err SlotMismatch
        ( BoundAwaitingAck slot facts, RegistrationTimedOut timedOut ) -> if slot == timedOut then Ok ( Absent, KillAndClear slot facts ) else Err SlotMismatch
        ( Registered slot facts, CleanupCompleted completed ) -> if slot == completed then Ok ( Unregistering slot facts, SendUnregister slot ) else Err SlotMismatch
        ( Unregistering slot _, UnregisterAcknowledged acknowledged ) -> if slot == acknowledged then Ok ( Absent, PermitFinal ) else Err SlotMismatch
        ( Unregistering slot _, UnregisterTimedOut timedOut ) -> if slot == timedOut then Ok ( Absent, PermitFinal ) else Err SlotMismatch
        _ -> Err UnexpectedEvent
