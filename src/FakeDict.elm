module FakeDict exposing (Dict, empty, insert, get, remove, keys)


type Dict key value
    = Dict (List ( key, value ))


empty : Dict key value
empty =
    Dict []


insert : key -> value -> Dict key value -> Dict key value
insert key value (Dict dict) =
    Dict (( key, value ) :: dict)


get : key -> Dict key value -> Maybe value
get expectedKey (Dict dict) =
    List.foldl
        (\( key, value ) prev ->
            case prev of
                Just found ->
                    Just found

                _ ->
                    if key == expectedKey then
                        Just value
                    else
                        Nothing
        )
        Nothing
        dict


remove : key -> Dict key value -> Dict key value
remove key (Dict dict) =
    Dict (List.filter (Tuple.first >> (/=) key) dict)


keys : Dict key value -> List key
keys (Dict dict) =
    dict |> List.map Tuple.first
