[Return to Home](/)

# Fullstack Roc + htmx—an early exploration 🔍📚🔭 

<time class="post-date" datetime="2023-12-15">15 Dec 2023</time>

With this exploration, I aimed to expand on one of the example apps for the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform and see if I could build a full-stack web application using the [htmx](https://htmx.org/) library.

I'm sharing code that isn't polished and continues to evolve as I learn more about Roc and htmx. I'm still working through the [Hypermedia Systems](https://hypermedia.systems) book and tinkering with different ideas. However, I want to share what I have, flaws and all, so that others can benefit from this exploration.

I hope this encourages people to build cool things. 

## Goals
1. Explore Roc and htmx for developing web applications
2. Learn more about Roc and htmx
3. Find issues and contribute fixes for the roc compiler and packages e.g. [lukewilliamboswell/roc-json](https://github.com/lukewilliamboswell/roc-json)

I found it very easy to work with Roc + htmx to build this demo app, and I feel confident my experience will scale to a larger app. I have a hobby project in mind I would like to start soon, and I look forward to extending the lessons here to build this using fullstack Roc.

I liked the simplicity of using Roc to build a webserver. The html and htmx libraries are conceptually very thin layers, so it was easy to reason about behaviour and focus on the interaction wanted. I'm not as familiar with web dev, so I feel most of my time was spent reading through the [Bootstrap](https://getbootstrap.com) docs.

I refactored multiple times, testing different ways to handle errors, work with sqlite, layout pages, and separate html views etc. The compiler was a helpful assistant, and I found myself making progressively larger changes and using `roc check` occasionally to see if I had introduced any errors.

## Demo

The code for this experiment is located at [lukewilliamboswell.github.io/content/roc-htmx-demo](https://github.com/lukewilliamboswell/lukewilliamboswell.github.io/tree/main/content/roc-htmx-demo). 

You can run the application using `DB_PATH=test.db roc dev main.roc`, provided you have `roc` and `sqlite3` in your environment PATH.

This application uses the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform which calls `main : Http.Request -> Task Http.Response []` on each http request.

Below is an illustration of the current application. It shows navigating between different pages, managing a task list, and logging into the application as a user. 

<img class="demo-img" src="/example-rhtmx.gif" alt="screen capture of the application being used"/>

## Session middleware

I wanted to track users across http calls, so wrote the following which creates and sets a cookie with a `sessionId : U64` value to be kept in the browser. I keep track of these sessions in a sqlite table and can associate these with a user to simulate being "logged in".

I think the future `Stored` ability would enable me to cache the session values in memory instead of calling out to sqlite on every request which would be a significant improvement if I was expecting a lot of traffic. The `Stored` ability will be introduced with the accepted [Task as Builtin](https://github.com/lukewilliamboswell/roc-awesome#task-as-builtin) design proposal.

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

## Request handling

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

## Error handling

For handling errors I used a single `handleErr` function to capture any unhandled errors. This task prints an error message to stderr, and responds with a server error. 

I found this to be useful for quickly identifying edge cases as I refactored various function implementations. 

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

Using a tag union `[SqliteErrorGetTask _, UnableToDecodeTask _]_` also helped to see all of the errors this task could return in one location. 

These error tags are also seamlessly merged into larger tag unions and handled by `handleErr` if not captured in the request handler. 

I liked using the [VS Code extension](https://github.com/ivan-demchenko/roc-vscode-unofficial) with the roc language server. If I wanted to see which errors are possible at a particular point I could hover over the type to see what the compiler had inferred. Below is an example of showing the full values for the `SqliteErrorCreatingTask _` tag.

<img class="demo-img" src="/ss-rls-errors.png" alt="screenshot showing language server providing error tag union" />

## Parsing URL Encoded values

[URL Encoded](https://en.wikipedia.org/wiki/Percent-encoding) values are returned by the browser when submitting a form. The function to parse these values is currently not available, so I wrote the following to do that.

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

I think I should be able to modify it to something like the following.

```roc 
keyStr <- key |> Str.fromUtf8 |> Result.mapErr (\_ -> InvalidUtf8Key) |> Result.try
```

## Query sqlite3 and return JSON

I wrote a `Task` which calls sqlite and returns the response encoded in [JSON](https://en.wikipedia.org/wiki/JSON) as a `List U8`.

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

## Login page

For the login page, I used [Bootstrap](https://getbootstrap.com) and the [Hasnep/roc-html](https://github.com/Hasnep/roc-html) package which were good to work with. I simply translated the html I wanted into Roc, for example `&lt;h5 class=&quot;card-title&quot;&gt;Login Form&lt;/h5&gt;` becomes `h5 [ class "card-title"] [ text "Login Form"]`.

I represented the different ways I wanted to render the login page using a tag union `[Fresh, UserNotProvided, UserNotFound Str]`. Using a payload with the username string was a nice way to provide feedback if the user input was invalid. 

```roc
loginPage : Session, [Fresh, UserNotProvided, UserNotFound Str] -> Html.Node
loginPage = \session, state ->

    (usernameInputClass, usernameValidationClass, usernameValidationText) = 
        when state is
            Fresh -> ("form-control", "invalid-feedback", "")
            UserNotFound str -> ("form-control is-invalid", "invalid-feedback", "Username \(str) not found")
            UserNotProvided -> ("form-control is-invalid", "invalid-feedback", "Missing username")

    layout LoginPage session [
        div [class "container"] [
            div [class "row justify-content-center"] [
                div [class "col-md-6 card"] [
                    div [class "card-body"] [
                        h5 [ class "card-title"] [ text "Login Form"],
                        form [class "container-fluid", action "/login", method "post"] [
                            div [class "col-auto"] [
                                label [class "col-form-label", for "loginUsername"] [text "Username"]
                            ],
                            div [class "col-auto"] [
                                input [class usernameInputClass, (attr "type") "username", (attr "required") "", id "loginUsername", name "user"] [],
                                div [class usernameValidationClass] [text usernameValidationText],
                            ],
                            div [class "col-auto"] [
                                label [class "col-form-label", for "loginPassword"] [text "Password (not used)"]
                            ],
                            div [class "col-auto"] [
                                input [class "form-control disabled", (attr "type") "password", (attr "disabled") "", id "loginPassword", name "pass"] []
                            ],
                            div [class "col-auto mt-2"] [
                                button [(attr "type") "submit", (attr "type") "button", class "btn btn-primary"] [text "Submit"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ]
```

## Using htmx to make an interactive table

I used htmx to delete tasks from the table of `AppTask`'s (unfortunately named similar to `Task` 😅). 

With `hx-target`, clicking the delete button will POST to the endpoint `/task/&ltid&gt/delete`. The server returns an updated table and swaps the rendered html into `#taskTable` without re-rendering the page. I like how simple the [Post/Redirect/Get pattern](https://en.wikipedia.org/wiki/Post/Redirect/Get) is to work with.

To make this more [REST](https://en.wikipedia.org/wiki/REST)ful I think I will update this to use `hx-delete` and remove the need for the additional `/delete` url segment.

```roc
listTaskView : List AppTask, Str -> Html.Node 
listTaskView = \tasks, taskQuery -> 
    if List.isEmpty tasks && Str.isEmpty taskQuery then 
        div [class "alert alert-info mt-2", role "alert"] [ text "Nil tasks, add a task to get started." ]
    else if List.isEmpty tasks then 
        div [class "alert alert-info mt-2", role "alert"] [ text "There are Nil tasks matching your query." ]
    else 

        tableRows = List.map tasks \task ->
                
            tr [] [
                td [(attr "scope") "row", class "col-6"] [text task.task],
                td [class "col-3 text-nowrap"] [text task.status],
                td [class "col-3"] [
                    div [class "d-flex justify-content-center"] [
                        a [ 
                            href "", 
                            hxPost "/task/\(Num.toStr task.id)/delete", 
                            hxTarget "#taskTable",
                            (attr "aria-label") "delete task",
                            (attr "style") "float: center;",
                        ] [
                            (el "button") [
                                (attr "type") "button", 
                                class "btn btn-danger",
                            ] [text "Delete"],
                        ]
                    ],
                ],
            ]

        table [
            id "taskTable",
            class "table table-striped table-hover table-sm mt-2",
        ] [
            thead [] [
                tr [] [
                    th [(attr "scope") "col", class "col-6"] [text "Task"],
                    th [(attr "scope") "col", class "col-3", (attr "rowspan") "2"] [text "Status"],
                ]
            ],
            tbody [] tableRows,
        ]
```

## Future Ideas

This is my progress so far in learning about Roc + htmx to build fullstack web apps. I will continue working on this as there are still plenty of other things I would like to learn.

I would also like to:
- Modify to use PostgreSQL so that I can use this to help test [agu-z/roc-pg](https://github.com/agu-z/roc-pg)
- Modify to help test [tweedegolf/nea](https://github.com/tweedegolf/nea) which aims to be a high performance webserver platform
- Build more functionality to explore htmx patterns further

I hope you have enjoyed reading this. 🎉

If you notice anything that could be improved or have any suggestions, please let me know 😎



