module Testable.EffectsLogTests (..) where

import ElmTest exposing (..)
import Testable.Effects as Effects
import Testable.EffectsLog as EffectsLog exposing (EffectsLog)
import Testable.Http as Http
import Testable.Task as Task


type MyWrapper a
  = MyWrapper a


httpGetAction : String -> String -> EffectsLog action -> Maybe ( action, EffectsLog action )
httpGetAction url responseBody =
  EffectsLog.httpAction
    { verb = "GET"
    , headers = []
    , url = url
    , body = Http.empty
    }
    (Http.ok responseBody)


all : Test
all =
  suite
    "Testable.EffectsLog"
    [ suite
        "resulting actions"
        [ EffectsLog.empty
            |> EffectsLog.insert (Http.getString "https://example.com/" |> Task.toResult |> Effects.task)
            |> fst
            |> httpGetAction "https://example.com/" "responseBody"
            |> Maybe.map fst
            |> assertEqual (Just <| Ok "responseBody")
            |> test "directly consuming the result"
        , EffectsLog.empty
            |> EffectsLog.insert (Http.getString "https://example.com/" |> Task.toResult |> Effects.task |> Effects.map MyWrapper)
            |> fst
            |> httpGetAction "https://example.com/" "responseBody"
            |> Maybe.map fst
            |> assertEqual (Just <| MyWrapper <| Ok "responseBody")
            |> test "mapping the result"
        , EffectsLog.empty
            |> EffectsLog.insert (Http.getString "https://example.com/" |> Task.toResult |> Effects.task)
            |> fst
            |> httpGetAction "https://XXXX/" "responseBody"
            |> Maybe.map fst
            |> assertEqual Nothing
            |> test "resolving a request that doesn't match gives Nothing"
        , EffectsLog.empty
            |> EffectsLog.insert (Effects.none |> Effects.map MyWrapper)
            |> fst
            |> httpGetAction "https://example.com/" "responseBody"
            |> Maybe.map fst
            |> assertEqual Nothing
            |> test "resolving a non-Http effect gives Nothing"
        ]
    ]
