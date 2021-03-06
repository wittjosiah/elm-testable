module Testable.TestContext exposing (Component, TestContext, startForTest, update, currentModel, assertCurrentModel, assertHttpRequest, assertNoPendingHttpRequests, resolveHttpRequest, advanceTime, assertCalled, find, thenFind, findAll, thenFindAll, trigger, assertText, assertNodeCount, assertPresent, assertAttribute)

{-| A `TestContext` allows you to manage the lifecycle of an Elm component that
uses `Testable.Effects`.  Using `TestContext`, you can write tests that exercise
the entire lifecycle of your component.

@docs Component, TestContext, startForTest, update

# Inspecting
@docs currentModel, assertCurrentModel, assertHttpRequest, assertNoPendingHttpRequests, assertCalled

# Html Matchers
@docs find, thenFind, findAll, thenFindAll, trigger, assertText, assertNodeCount, assertPresent, assertAttribute

# Simulating Effects
@docs resolveHttpRequest, advanceTime
-}

import Expect exposing (Expectation)
import String
import Testable.Cmd
import Testable.EffectsLog as EffectsLog exposing (EffectsLog, containsCmd)
import Testable.Http as Http
import Testable.Html.Types as Html
import Testable.Html.Internal as HtmlInternal
import Time exposing (Time)
import Platform.Cmd


{-| A component that can be used to create a `TestContext`
-}
type alias Component msg model =
    { init : ( model, Testable.Cmd.Cmd msg )
    , update : msg -> model -> ( model, Testable.Cmd.Cmd msg )
    , view : model -> Html.Node msg
    }


{-| The representation of the current state of a testable component, including
a representaiton of any pending Effects.
-}
type TestContext msg model
    = TestContext
        { component : Component msg model
        , state :
            Result (List String)
                { model : model
                , effectsLog : EffectsLog msg
                }
        , query : Html.Query
        }


{-| Create a `TestContext` for the given Component
-}
startForTest : Component msg model -> TestContext msg model
startForTest component =
    let
        ( initialState, initialEffects ) =
            component.init
    in
        TestContext
            { component = component
            , state =
                Ok
                    { model = initialState
                    , effectsLog = EffectsLog.empty
                    }
            , query = Html.Multiple []
            }
            |> applyEffects initialEffects


{-| Apply an msg to the component in a given TestContext
-}
update : msg -> TestContext msg model -> TestContext msg model
update msg (TestContext context) =
    case context.state of
        Ok state ->
            let
                ( newModel, newEffects ) =
                    context.component.update msg state.model
            in
                TestContext
                    { context
                        | state = Ok { state | model = newModel }
                    }
                    |> applyEffects newEffects

        Err errors ->
            TestContext
                { context
                    | state = Err (("update " ++ toString msg ++ " applied to an TestContext with previous errors") :: errors)
                }


applyEffects : Testable.Cmd.Cmd msg -> TestContext msg model -> TestContext msg model
applyEffects newEffects (TestContext context) =
    case context.state of
        Err errors ->
            TestContext context

        Ok { model, effectsLog } ->
            case EffectsLog.insert newEffects effectsLog of
                ( newEffectsLog, immediateMsgs ) ->
                    List.foldl update
                        (TestContext
                            { context
                                | state =
                                    Ok
                                        { model = model
                                        , effectsLog = newEffectsLog
                                        }
                            }
                        )
                        immediateMsgs


{-| Assert that a given Http.Request has been made by the component under test
-}
assertHttpRequest : Http.Settings -> TestContext msg model -> Expectation
assertHttpRequest settings (TestContext context) =
    case context.state of
        Err errors ->
            Expect.fail
                ("Expected an HTTP request to have been made:"
                    ++ "\n    Expected: "
                    ++ toString settings
                    ++ "\n    Actual:"
                    ++ "\n      TestContext had previous errors:"
                    ++ String.join "\n        " ("" :: errors)
                )

        Ok { model, effectsLog } ->
            if EffectsLog.containsHttpMsg settings effectsLog then
                Expect.pass
            else
                Expect.fail
                    ("Expected an HTTP request to have been made:"
                        ++ "\n    Expected: "
                        ++ toString settings
                        ++ "\n    Actual: "
                        ++ toString effectsLog
                    )


{-| Simulate an HTTP response to a request made with the given Http settings
-}
resolveHttpRequest : Http.Settings -> Result Http.Error (Http.Response String) -> TestContext msg model -> TestContext msg model
resolveHttpRequest settings response (TestContext context) =
    case context.state of
        Err errors ->
            TestContext
                { context
                    | state = Err (("resolveHttpRequest " ++ toString settings ++ " applied to an TestContext with previous errors") :: errors)
                }

        Ok { model, effectsLog } ->
            case
                EffectsLog.httpMsg settings response effectsLog
                    |> Result.fromMaybe ("No pending HTTP request: " ++ toString settings)
            of
                Ok ( newLog, msgs ) ->
                    List.foldl update
                        (TestContext { context | state = Ok { model = model, effectsLog = newLog } })
                        msgs

                Err message ->
                    TestContext { context | state = Err [ message ] }


{-| Ensure that there are no pending HTTP requests
-}
assertNoPendingHttpRequests : TestContext msg model -> Expectation
assertNoPendingHttpRequests (TestContext context) =
    case context.state of
        Err errors ->
            Expect.fail
                ("Expected no pending HTTP requests, but TestContext had previous errors:"
                    ++ String.join "\n    " ("" :: errors)
                )

        Ok { effectsLog } ->
            Expect.equal [] (EffectsLog.httpRequests effectsLog)


{-| Simulate the passing of time
-}
advanceTime : Time -> TestContext msg model -> TestContext msg model
advanceTime milliseconds (TestContext context) =
    case context.state of
        Err errors ->
            TestContext
                { context
                    | state = Err (("advanceTime " ++ toString milliseconds ++ " applied to an TestContext with previous errors") :: errors)
                }

        Ok { model, effectsLog } ->
            case
                EffectsLog.sleepMsg milliseconds effectsLog
            of
                ( newLog, msgs ) ->
                    List.foldl update
                        (TestContext { context | state = Ok { model = model, effectsLog = newLog } })
                        msgs


{-| Get the current state of the component under test
-}
currentModel : TestContext msg model -> Result (List String) model
currentModel (TestContext context) =
    context.state |> Result.map .model


{-| A convenient way to assert about the current state of the component under test
-}
assertCurrentModel : model -> TestContext msg model -> Expectation
assertCurrentModel expectedModel context =
    context
        |> currentModel
        |> Expect.equal (Ok expectedModel)


{-| Assert that a cmd was called
-}
assertCalled : Platform.Cmd.Cmd msg -> TestContext msg model -> Expectation
assertCalled expectedCmd (TestContext context) =
    case context.state of
        Err errors ->
            Expect.fail
                ("Expected that a cmd was called, but TestContext had previous errors:"
                    ++ String.join "\n    " ("" :: errors)
                )

        Ok { effectsLog } ->
            if containsCmd expectedCmd effectsLog then
                Expect.pass
            else
                Expect.equal [ expectedCmd ] (EffectsLog.wrappedCmds effectsLog)


{-| Finds a single html node in the view
-}
find : List Html.Selector -> TestContext msg model -> TestContext msg model
find query (TestContext context) =
    TestContext { context | query = (Html.Single query) }


{-| Finds a children node from the current found nodes
-}
thenFind : List Html.Selector -> TestContext msg model -> TestContext msg model
thenFind query (TestContext context) =
    TestContext { context | query = (Html.Children context.query (Html.Single query)) }


{-| Finds all html nodes in the view
-}
findAll : List Html.Selector -> TestContext msg model -> TestContext msg model
findAll query (TestContext context) =
    TestContext { context | query = (Html.Multiple query) }


{-| Finds all children node from the current found nodes
-}
thenFindAll : List Html.Selector -> TestContext msg model -> TestContext msg model
thenFindAll query (TestContext context) =
    TestContext { context | query = (Html.Children context.query (Html.Multiple query)) }


findNodesForContext : TestContext msg model -> Result (List String) (List (Html.Node msg))
findNodesForContext (TestContext context) =
    case context.state of
        Err errors ->
            Err errors

        Ok { model } ->
            context.component.view model
                |> HtmlInternal.findNodes context.query
                |> Ok


{-| Write an assetion based on the node text
-}
assertText : (String -> Expectation) -> TestContext msg model -> Expectation
assertText expectation (TestContext context) =
    case findNodesForContext (TestContext context) of
        Err errors ->
            Expect.fail
                ("Tried to get text from the view, but TestContext had previous errors:"
                    ++ String.join "\n    " ("" :: errors)
                )

        Ok nodesFound ->
            if List.isEmpty nodesFound then
                Expect.fail <| "Could not find any element with the query " ++ toString context.query
            else
                nodesFound
                    |> List.map (HtmlInternal.nodeText)
                    |> String.join ""
                    |> expectation


{-| Write an assetion based on the amount of nodes found
-}
assertNodeCount : (Int -> Expectation) -> TestContext msg model -> Expectation
assertNodeCount expectation (TestContext context) =
    case findNodesForContext (TestContext context) of
        Err errors ->
            Expect.fail
                ("Tried to get text from the view, but TestContext had previous errors:"
                    ++ String.join "\n    " ("" :: errors)
                )

        Ok nodesFound ->
            nodesFound
                |> List.length
                |> expectation


{-| Write an assetion based on the node text
-}
assertAttribute : String -> (String -> Expectation) -> TestContext msg model -> Expectation
assertAttribute attributeName expectation (TestContext context) =
    case findNodesForContext (TestContext context) of
        Err errors ->
            Expect.fail
                ("Tried to get text from the view, but TestContext had previous errors:"
                    ++ String.join "\n    " ("" :: errors)
                )

        Ok nodesFound ->
            if List.length nodesFound > 1 then
                Expect.fail <| "Found more than one element to assert attribute with the query " ++ toString context.query
            else
                case List.head nodesFound of
                    Just node ->
                        case HtmlInternal.attributeValueByName attributeName node of
                            Ok value ->
                                expectation value

                            Err error ->
                                Expect.fail error

                    Nothing ->
                        Expect.fail <| "Could not find and element with the query " ++ toString context.query ++ " probably you didn't wanted to assert all nodes, use find instead of findAll"


{-| Assert that some node was found with the specified query
-}
assertPresent : TestContext msg model -> Expectation
assertPresent =
    assertNodeCount (Expect.equal 1)


{-| Trigger node events
-}
trigger : String -> String -> TestContext msg model -> TestContext msg model
trigger name event (TestContext context) =
    case findNodesForContext (TestContext context) of
        Err errors ->
            TestContext
                { context
                    | state = Err (("trigger " ++ name ++ " " ++ event ++ " applied to an TestContext with previous errors") :: errors)
                }

        Ok nodesFound ->
            if List.length nodesFound > 1 then
                TestContext { context | state = Err [ "Found more than one element to trigger event with the query " ++ toString context.query ++ " probably you didn't wanted to trigger events on all nodes, use find instead of findAll" ] }
            else
                case List.head nodesFound of
                    Just node ->
                        case (HtmlInternal.triggerEvent node name event) of
                            Ok msg ->
                                update msg (TestContext context)

                            Err err ->
                                (TestContext { context | state = Err [ err ] })

                    Nothing ->
                        TestContext { context | state = Err [ "Could not find and element with the query " ++ toString context.query ] }
