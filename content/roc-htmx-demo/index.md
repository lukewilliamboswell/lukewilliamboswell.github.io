[Return to Home](/)

# Fullstack Roc + htmx—an early exploration 🔍📚🔭 

<time class="post-date" datetime="2023-12-14">14 Dec 2023</time>

With this exploration, I aimed to expand on one of the example apps for the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform, and see if I could build a full-stack web application using the [htmx](https://htmx.org/) library.

I hope this post encourages other people to build cool things.

## Goals
- Explore Roc and htmx for developing web applications
- Learn more about Roc and htmx
- Find issues and contribute fixes for the roc compiler and packages e.g. [lukewilliamboswell/roc-json](https://github.com/lukewilliamboswell/roc-json)

## Summary

The code for this experiment is located at [lukewilliamboswell.github.io/content/roc-htmx-demo](https://github.com/lukewilliamboswell/lukewilliamboswell.github.io/tree/main/content/roc-htmx-demo). 

You can run the application using `DB_PATH=test.db roc dev main.roc`, provided you have `roc` and `sqlite3` in your environment PATH.

This application uses the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform which calls `main : Http.Request -> Task Http.Response []` on each http request.

### Future Ideas

- Modify to use PostgreSQL so that I can use this to help test [agu-z/roc-pg](https://github.com/agu-z/roc-pg)
- Modify to help test the [tweedegolf/nea](https://github.com/tweedegolf/nea)

## Observations

### Session Middle-ware

I wanted to track users across http calls, so wrote the following which creates and sets a cookie with a `sessionId : U64` value. I keep track of these sessions in a sqlite table and can associate these with a user to simulate being "logged in".

I think the future `Stored` ability would enable you to cache the session values instead of using sqlite which would be a significant improvement.

```roc
maybeSession <- parseSessionId req |> getSession dbPath |> Task.attempt
when maybeSession is

    # Session cookie should be sent with each request
    Ok session -> handleReq session dbPath req |> Task.onErr handleErr

    # If this is a new session we should create one and return it
    Err SessionNotFound -> 

        maybeNewSession <- newSessionId dbPath |> Task.attempt

        when maybeNewSession is 
            Err err -> handleErr err
            Ok sessionId -> 
                
                Task.ok {
                    status: 303,
                    headers: [
                        { name: "Set-Cookie", value: Str.toUtf8 "sessionId=\(Num.toStr sessionId)" },
                        { name: "Location", value: Str.toUtf8 req.url },
                    ],
                    body: [],
                }

    # Handle any server errors
    Err err -> handleErr err
```

### Request Handler

For routing the request, I separated the url into segements and used pattern matching on a `List Str`. This worked well and was easy to follow. 

I'm not sure how well this scales for a larger application, but it was easy to get started and I was able to re-factor easily. For example, I added a `Session` argument so that the handlers would have that information available.

```roc
handleReq : Session, Str, Request -> Task Response _
handleReq = \session, dbPath, req ->
    when (req.method, req.url |> Url.fromStr |> urlSegments) is
        (Get, [""]) -> indexPage session |> htmlResponse |> Task.ok
        (Get, ["robots.txt"]) -> staticReponse robotsTxt
        (Get, ["styles.css"]) -> staticReponse stylesFile
        (Get, ["site.js"]) -> staticReponse siteFile
        (Get, ["contact"]) -> 

            contacts <- getContacts |> Task.map 

            contacts |> listContactView |> htmlResponse 

        (Get, ["login"]) -> 

            loginPage session Fresh |> htmlResponse |> Task.ok

        (Post, ["login"]) ->

            params = parseFormUrlEncoded (parseBody req) 

            when Dict.get params "user" is 
                Err _ -> loginPage session UserNotProvided |> htmlResponse |> Task.ok
                Ok username -> 
                    loginUser dbPath session.id username
                    |> Task.attempt \result -> 
                        when result is 
                            Ok {} -> redirect "/"
                            Err (UserNotFound _) -> loginPage session (UserNotFound username) |> htmlResponse |> Task.ok
                            Err err -> handleErr err

        # ... etc
```

### Error Handler

For handling errors from various handlers I chose to use a single `handleErr` function to capture and unhandled errors and print these to stderr, and return an http server error to the browser. I found this to be very useful for quickly identifying edge cases and was very easy to manage. 

Various tasks such as `getAppTasks` would call out to sqlite and I wrapped the errors with custom tags such as `SqliteErrorGetTask` or `UnableToDecodeTask` which made it much easier to identify where the error may have originated from.

```roc
handleErr : _ -> Task Response []_
handleErr = \err ->

    (msg, code) = when err is 
        URLNotFound url -> (Str.joinWith ["404 NotFound" |> Color.fg Blue, url] " ", 404)
        _ -> (Str.joinWith ["SERVER ERROR" |> Color.fg Red,Inspect.toStr err] " ", 500) 
         

    {} <- Stderr.line msg |> Task.await

    Task.ok {
        status: code,
        headers: [],
        body: [],
    }

# examples of various errors
deleteAppTask : Str, Str -> Task {} [SqliteErrorDeletingTask _]_
createAppTask : Str, AppTask -> Task {} [TaskWasEmpty, SqliteErrorCreatingTask _]_
getAppTasks : Str, Str -> Task (List AppTask) [SqliteErrorGetTask _, UnableToDecodeTask _]_
executeSql : Str, Str -> Task (List U8) _
```

### Parsing FormURLEncoded 

[URL / Percent Encoded](https://en.wikipedia.org/wiki/Percent-encoding) values are returned by the browser when submitting a form. The function to parse these values is currently not available, so I wrote the following to do that.

This was quick to write and worked well for my immediate needs. However I think I should re-write this to return a `Result (Dict Str Str) [InvalidUtf8Key, InvalidUtf8Value]` or similar, instead of crashing which is pretty hacky.

```roc
parseFormUrlEncoded : List U8 -> Dict Str Str
parseFormUrlEncoded = \bytes ->

    go = \bytesRemaining, state, key, chomped, dict ->
        next = List.dropFirst bytesRemaining 1
        when bytesRemaining is
            [] if List.isEmpty chomped -> dict
            [] ->
                # chomped last value
                keyStr = key |> Str.fromUtf8 |> unwrap "chomped invalid utf8 key"
                valueStr = chomped |> Str.fromUtf8 |> unwrap "chomped invalid utf8 value"

                Dict.insert dict keyStr valueStr

            ['=', ..] -> go next ParsingValue chomped [] dict # put chomped into key
            ['&', ..] ->
                keyStr = key |> Str.fromUtf8 |> unwrap "chomped invalid utf8 key"
                valueStr = chomped |> Str.fromUtf8 |> unwrap "chomped invalid utf8 value"

                go next ParsingKey [] [] (Dict.insert dict keyStr valueStr)

            ['%', firstByte, secondByte, ..] ->
                hex = Num.toU8 (hexBytesToU32 [firstByte, secondByte])

                go (List.dropFirst next 2) state key (List.append chomped hex) dict

            [first, ..] -> go next state key (List.append chomped first) dict

    go bytes ParsingKey [] [] (Dict.empty {})
```