module Schelm.Node.ChildProcess.ParentAdapter exposing (Prepared, Slot, Event(..), prepare, prepared)
{-| Protocol-only parent watchdog boundary. No harness transport is implemented here.
@docs Prepared, Slot, Event, prepare, prepared
-}
{-| Prepared parent capability. -}
type Prepared = Prepared
{-| Parent slot. -}
type Slot = Slot Int
{-| Parent protocol event. -}
type Event = PrepareRequested | BindRequested Slot { pid : Int, pgid : Int } | UnregisterRequested Slot
type alias PreparedFacts = { slot : Slot }
{-| Request preparation before spawn. -}
prepare : Event
prepare = PrepareRequested
{-| Construct acknowledged prepared facts at the external boundary. -}
prepared : Int -> PreparedFacts
prepared n = { slot = Slot n }
