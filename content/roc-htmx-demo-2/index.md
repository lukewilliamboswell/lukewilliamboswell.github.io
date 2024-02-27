[Return to Home](/)

# Fullstack Roc + htmx - Events 

<time class="post-date" datetime="2024-02-27">27 Feb 2024</time> *~15 mins reading time*

I want to share what I have learnt about [htmx events](https://htmx.org/examples/update-other-content/#events) by experimenting with [lukewilliamboswell/roc-htmx-playground](https://github.com/lukewilliamboswell/roc-htmx-playground/).

This is an extension from my previous article, [Fullstack Roc + htmx—an early exploration](/roc-htmx-demo). Since that post, I've made the following changes;
- Moved the app into a repository so that others can also experiment with it.
- Implemented an API for `SQLite` in the [roc-lang/basic-webserver](https://github.com/roc-lang/basic-webserver) platform.
- Refactored from a single file to use a more modular structure with Interface modules.
- Implemented a [Nested Set](https://en.wikipedia.org/wiki/Nested_set_model) type to represent a hierarchy of `Todo`'s in SQL.
- Added a `TreeView` page to display `Todo`'s in a tree view, instead of just the previous table.

These are the steps I cover in this article. 

- [Demonstration](#demo)
- [Events](#nested-sets)
 - [Overview](#overview)
 - [Step 1 Navigate to TreeView Page](#step1)
 - [Step 2 & 7 Retrieve Todos from SQLite](#step2)
 - [Step 3 Render TreeView Page](#step3)
 - [Step 4 Click Todo Checkbox](#step4)
 - [Step 5 Update SQL then HX-Trigger response](#step5)
 - [Step 6 Handle Event](#step6)
 - [Step 8 Re-render TreeView](#step8)
- [Reflection](#reflection)

But first, here is a demonstration of the work in progress.

# [Demonstration](#demo) {#demo}

Code available at [this commit](https://github.com/lukewilliamboswell/roc-htmx-playground/tree/c23869de93dff8a22006639d4aef243c38130eb4). 

This shows the same `Todos` displayed in both a list and a tree view. They are being updated using htmx events which trigger a re-render of the views.

<img class="demo-img" src="/roc-htmx-demo-2/demo.gif" alt="screen capture of the application being used"/>

# [Events](#nested-sets) {#nested-sets}

You can read about htmx events [here](https://htmx.org/docs/#triggers), specifically the various ways you can trigger AJAX requests. The `hx-trigger` attribute is used to listen for a specific event, such as a user clicking on a checkbox. 

For this demo I am using the following feature, it's also explained in the htmx example [update-other-content](https://htmx.org/examples/update-other-content/#events);
 
> `from: &lt;CSS Selector&gt;` listen for the event on a different element.

I think I could have implemented the functionality demonstrated here without using a client-side event, by using multiple endpoints. However, I wanted to try out the event oriented design instead.

## [Overview](#overview) {#overview}

The following diagram illustrates a sequence of events, from when a user navigates to the page, and clicks a checkbox, through to when htmx swaps out the content and re-renders the view. 

You can see the requests and responses between the client (browser) and server (roc) starting from the top.

<img class="demo-img" src="/roc-htmx-demo-2/event-sequence.svg" alt="illustration of the sequence for a htmx event"/>

## [Step 1 Navigate to TreeView Page](#step1) {#step1}

The user navigates to `/treeview` and the server responds with the html for the `TreeView` page.

```roc
# src/main.roc

handleReq : Session, Str, Request -> Task Response _
handleReq = \session, dbPath, req ->

        # .. other handlers

        (Get, ["treeview"]) -> # handler for "/treeview"

            # get the todos from the db in a tree structure
            nodes <- Sql.Todo.tree { path: dbPath, userId: 1 } |> Task.await

            # render the page html with the todos displayed in a tree
            Pages.TreeView.view { session, nodes } |> htmlResponse |> Task.ok
```

## [Step 2 & 7 Retrieve Todos from SQLite](#step2) {#step2}

The server retrieves the `Todo`'s from the SQLite database and returns them as a tree structure.

Each row of the query is of the form `[Integer id, String task, String status, Integer left, Integer right]` where the `left` and `right` values are used to represent the hierarchy of the `Todo`'s in a [Nested Set](https://en.wikipedia.org/wiki/Nested_set_model). In this representation, a node is a child if its `left` and `right` values are within the range of its parent's `left` and `right` values.

```roc
# src/Sql/Todo.roc

tree : { path : Str, userId : U64 } -> Task (Tree Todo) _
tree = \{ path, userId } ->

    # SQL query to get the todos
    query =
        """
        SELECT 
            tasks.id,
            tasks.task,
            tasks.status,
            TaskHeirachy.lft,
            TaskHeirachy.rgt
        FROM
            users
            JOIN TaskHeirachy ON users.user_id = TaskHeirachy.user_id
            JOIN tasks ON TaskHeirachy.task_id = tasks.id
        WHERE
            users.user_id = :user_id
        ORDER BY
            TaskHeirachy.lft;
        """

    bindings = [{ name: ":user_id", value: Num.toStr userId }]

    SQLite3.execute { path, query, bindings }
    |> Task.mapErr SqlError
    |> Task.await \rows -> parseTreeRows rows [] |> Task.fromResult

parseTreeRows : List (List SQLite3.Value), List (NestedSet Todo) -> Result (Tree Todo) _
parseTreeRows = \rows, acc ->
    when rows is

        # base case, translate the `acc` from `NestedSet`s to a `Tree`
        [] -> Model.nestedSetToTree acc |> Ok

        # recursive case, parse the rows and build up the `acc` list of `NestedSet`s
        [[Integer id, String task, String status, Integer left, Integer right], .. as rest] ->
            todo : Todo
            todo = { id, task, status }

            parseTreeRows rest (List.append acc { value: todo, left, right })

        _ -> Inspect.toStr rows |> UnexpectedSQLValues |> Err
```

## [Step 3 Render TreeView Page](#step3) {#step3}

In the code below we can see how the `hx-put` attribute on the checkbox triggers a `PUT` request when the checkbox is clicked.

```roc
# src/Pages/TreeView.roc

# view function to render the `Todo`s in a tree view
nodesView : Tree Todo -> Html.Node
nodesView = \node ->
    when node is

        # empty tree, render a message
        Empty -> Html.li [] [Html.text "EMPTY"]

        # non-empty tree, render the `Todo` and its children recursively
        Node todo children ->

            # switch on the status of the todo to render the checkbox as either checked or not
            checkbox = 
                if todo.status == "Completed" then
                    checkboxElem todo.task (Num.toStr todo.id) Checked
                else 
                    checkboxElem todo.task (Num.toStr todo.id) NotChecked

            Html.li [] [
                Html.span [] [checkbox],
                Html.ul 
                    [class "todo-tree-ul"] 
                    (List.map children nodesView),
                    # we use recursion to render each of the child nodes
            ]

# helper view to render a single checkbox
checkboxElem = \str, taskIdStr, check ->
    (checkAttrs) = 
        when check is 
            Checked -> 
                ([
                    # clicks will tigger a PUT request to /task/2/in-progress
                    (attribute "hx-put") "/task/$(taskIdStr)/in-progress",
                    # .. other attributes
                ]) 
            NotChecked -> 
                ([
                    # clicks will trigger a PUT request to /task/2/complete
                    (attribute "hx-put") "/task/$(taskIdStr)/complete",
                    # .. other attributes
                ])

    Html.div [class "form-check"] [
        Html.input checkAttrs [],
        Html.label [
            class "form-check-label",
        ] [
            Html.text str
        ],
    ]
```

## [Step 4 Click Todo Checkbox](#step4) {#step4}

The below image and html show the `Todo`'s displayed in a tree view with checkboxes. When a user clicks a checkbox, a `PUT` request is sent to the server to update the status of the `Todo`.

<img class="demo-img" src="/roc-htmx-demo-2/todo-tree-view.png" height="100px" alt="screen capture of the todo tree view"/>

```xml
<div class="row justify-content-center">
    <ul class="todo-tree-ul">
        <li><span>
                <div class="form-check">
                    <input hx-put="/task/0/in-progress" class="form-check-input" type="checkbox" value="" checked="">
                    <label class="form-check-label">Buy groceries</label>
                    <!-- note the hx-put attribute on the input element -->
                </div>
            </span>
            <ul class="todo-tree-ul">
                <li>
                    <span>
                        <div class="form-check">
                            <input hx-put="/task/1/complete" class="form-check-input" type="checkbox" value="">
                            <label class="form-check-label">Finish that assignment</label>
                        </div>
                    </span>
                    <ul class="todo-tree-ul"></ul>
                </li>
                <!-- other elements removed -->
            </ul>
        </li>
    </ul>
</div>
```

## [Step 5 Update SQL then HX-Trigger response](#step5) {#step5}

After the server updates the DB, it responds with a header `HX-Trigger: todosUpdated`.

```roc
# src/main.roc

handleReq : Session, Str, Request -> Task Response _
handleReq = \session, dbPath, req ->

        # .. other handlers removed

        (Put, ["task", taskIdStr, "complete"]) -> # handler for "/task/<id>/complete"

            {} <- Sql.Todo.update { path: dbPath, taskIdStr, action: Completed } |> Task.await

            triggerResponse "todosUpdated"

        (Put, ["task", taskIdStr, "in-progress"]) -> # handler for "/task/<id>/in-progress"

            {} <- Sql.Todo.update { path: dbPath, taskIdStr, action: InProgress } |> Task.await

            triggerResponse "todosUpdated"

triggerResponse : Str -> Task Response []_
triggerResponse = \trigger ->
    Task.ok {
        status: 200,
        headers: [
            { name: "HX-Trigger", value: Str.toUtf8 trigger },
        ],
        body: [],
    }
```

## [Step 6 Handle Event](#step6) {#step6}

The `(attribute "hx-trigger") "todosUpdated from:body"` registers a listener for the `todosUpdated` event on the body element. 

When the `todosUpdated` event is triggered by the response, it bubbles up to the `body` element which then triggers the page to render.

```roc
# src/Pages/TreeView.roc

view : {
    session : Session,
    nodes : Tree Todo,
} -> Html.Node
view = \{ session, nodes } ->
    layout
        {
            session,
            description: "TREE VIEW PAGE",
            title: "TREE VIEW",
            navLinks: NavLinks.navLinks "TreeView",
        }
        [
            Html.div [
                class "container",
                (attribute "hx-trigger") "todosUpdated from:body" # listen for the `todosUpdated` event
                (attribute "hx-get") "/treeview", # send an AJAX request to get the page
                (attribute "hx-target") "body", # then swap the html into the body element
            ] [
                Html.div [class "row justify-content-center"] [
                    Html.ul [
                        class "todo-tree-ul",
                    ] [
                        nodesView nodes 
                    ]
                ],
            ],
        ]
```

## [Step 8 Re-render TreeView](#step8) {#step8}

The html that is returned from the server is displayed to the user in the browser, which is similar to [Step 3](#step3).

However, unlike in that step htmx will swap out the content of the `body` element with the new html. This doesn't require the page and other assets like css and js to be reloaded.

When the event is triggered, the attribute `(attribute "hx-get") "/treeview"` directs that an AJAX request be sent to `/treeview` and then `(attribute "hx-target") "body"` instructs the response html to be swapped into the `body`. This can be seen in the [Step 6](#step6) code example. 

# [Reflection](#reflection) {#reflection}

Working with events like this in htmx feels good. It's a nice way to structure the client and server code and I think it's a good fit for building a web application with `roc`.

I would like to add more features to the `TreeView` page, such as the ability to add and delete `Todo`'s, or to re-order them in the tree. I think this will be a good way to explore more of the tradeoffs around nested sets, and also to further explore events.

I have found SQLite to be nice to work with. In particular, I like how easy it is to parse the results into various structures. I would like to test SQLite transactions. I suspect the current implementation may not support it at this time, so I may need to revisit that design.

I hope you enjoyed reading this article. If you have any feedback or ideas, please let me know.



