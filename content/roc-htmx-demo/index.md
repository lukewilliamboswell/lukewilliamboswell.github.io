[Return to Home](/)

# Fullstack Roc + htmx—an early exploration 🔍📚🔭 

<time class="post-date" datetime="2023-12-14">14 Dec 2023</time>

With this exploration, I aimed to expand on one of the example apps for the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform and see if I could build a full-stack web application using the [htmx](https://htmx.org/) library.

I'm sharing code that isn't polished and continues to evolve as I learn more about Roc and htmx. However, I want to share what I have, flaws and all, so that others can benefit from this exploration.

I hope this encourages people to build cool things. 

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
- Modify to help test [tweedegolf/nea](https://github.com/tweedegolf/nea) which aims to be a high performance webserver platform

### Demonstration

Below is an illustration of the current application. It shows navigating between different pages, managing a task list, and logging into the application as a user. 

<img class="demo-img" src="/example-rhtmx.gif" alt="screen capture of the application being used"/>

## Observations

### Session Middle-ware

I wanted to track users across http calls, so wrote the following which creates and sets a cookie with a `sessionId : U64` value to be kept in the browser. I keep track of these sessions in a sqlite table and can associate these with a user to simulate being "logged in".

I think the future `Stored` ability would enable me to cache the session values in memory instead of calling out to sqlite on every request which would be a significant improvement if I was expecting a lot of traffic. 

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

### Request Handling

For routing the request, I used pattern matching on a tag for the method and `List Str` for url segments. This worked well and was easy to follow. 

I'm not sure how well this scales for a larger application, but it was simple to get started with, and easy to re-factor as I needed, e.g. when I included the `dbPath : Str` and `session : Session` arguments.

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

For handling errors I used a single `handleErr` function to capture any unhandled errors. This task prints an error message to stderr, and responds with a server error. 

I found this to be useful for quickly identifying edge cases as I continuously refactored various implementation and function signatures. 

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

Various tasks such as `getAppTasks` would call out to sqlite and I wrapped the errors with custom tags such as `SqliteErrorGetTask` or `UnableToDecodeTask` which made it much easier to identify where the error originated.

Using a tag union `[SqliteErrorGetTask _, UnableToDecodeTask _]_` also helped to see all of the errors this task could possibly return in one location. 

These error tags are also seamlessly merged into larger tag unions and handled by `handleErr` if not captured in the request handler. 

Another helpful feature was the roc language server. If I wanted to see which errors are possible at a particular point I could hover over the type to see what the compiler had inferred. Below is an example of showing the full values for the `SqliteErrorCreatingTask _` tag.

<img class="demo-img" src="/ss-rls-errors.png" alt="screenshot showing language server providing error tag union" />

### Parsing FormURLEncoded 

[URL / Percent Encoded](https://en.wikipedia.org/wiki/Percent-encoding) values are returned by the browser when submitting a form. The function to parse these values is currently not available, so I wrote the following to do that.

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

unwrap = \thing, msg ->
    when thing is
        Ok unwrapped -> unwrapped
        Err _ -> crash "CRASHED \(msg)"
```

This was quick to write and worked well for my immediate needs. However I think I will re-write this to return a `Result (Dict Str Str) [InvalidUtf8Key, InvalidUtf8Value]` or similar, instead of crashing which is a bit hacky. 

I think I should be able to modify to something like the following.

```roc 
keyStr <- key |> Str.fromUtf8 |> Result.mapErr (\_ -> InvalidUtf8Key) |> Result.try
```

### Query Sqlite3 and return JSON

I wrote a `Task` which calls sqlite and returns the response encoded in JSON.

```roc
executeSql : Str, Str -> Task (List U8) _
executeSql = \query, dbPath ->
    output <-
        Command.new "sqlite3"
        |> Command.arg dbPath
        |> Command.arg ".mode json"
        |> Command.arg query
        |> Command.output
        |> Task.await

    when output.status is
        Err _ -> Task.err (SqlError output.stderr)
        Ok {} -> 
            if List.isEmpty output.stdout then 
                Task.err NilRows
            else 
                Task.ok output.stdout            
```

Here are a couple of examples where I use this task. I am particularly happy with being able to pipeline this function with the SQL query as I think it is much easier to follow the logic of what is happening here. 

```roc
findUser : Str, Str -> Task {id : U64, username : Str} _
findUser = \dbPath, username ->
    """
    SELECT user_id as userId FROM users WHERE name = '\(escapeSQL username)';
    """
    |> executeSql dbPath
    |> Task.await \bytes ->
        when Decode.fromBytes bytes json is 
            Err msg -> Task.err (ErrParsingJson msg bytes)
            Ok userList ->
                userList
                |> List.first 
                |> Result.map \{userId} -> {id: userId, username}
                |> Task.fromResult
    |> Task.mapErr \err -> if err == NilRows then UserNotFound username else err

loginUser : Str, U64, Str -> Task {} _
loginUser = \dbPath, sessionId, username ->

    user <- findUser dbPath username |> Task.await

    """
    UPDATE sessions
    SET user_id = \(Num.toStr user.id)
    WHERE session_id = \(Num.toStr sessionId);
    """
    |> executeSql dbPath
    |> Task.attempt \result ->
        when result is 
            Err NilRows -> Task.ok {}
            Ok _ -> Task.ok {}
            Err err -> Task.err err
```