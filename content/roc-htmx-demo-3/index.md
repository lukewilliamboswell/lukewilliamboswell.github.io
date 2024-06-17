[Return to Home](/)

# Fullstack Roc + htmx—Data Table

<time class="post-date" datetime="2024-06-20">20 Jun 2024</time> *~15 mins reading time*

In this article I continue experimenting with [lukewilliamboswell/roc-htmx-playground](https://github.com/lukewilliamboswell/roc-htmx-playground/) and build a Data Table. The inspiration for this comes from the idea of having a table in an SQL database, and wanting a simple way to display and edit this using fullstack roc + htmx.

There were a few things I wanted to explore with this including; making individual columns sortable, pagination and filtering the table results, making a download button to get the data as a CSV.

In summary I have been very pleased with the experience writing this demo, and I am convinced this will be a great way to build larger web applications in the future as roc matures.

Here is a demonstration of the data table in action.

# [Demonstration](#demo) {#demo}

Code for this article available at [this commit](https://github.com/lukewilliamboswell/roc-htmx-playground/tree/18c94a7afa1e10767c209c5e1b7538ce31eca12d).

<img class="demo-img" src="/roc-htmx-demo-3/demo.gif" alt="screen capture of the application being used"/>

# [Refactor into Model-View-Controller](#mvc) {#mvc}

While writing the roc code for this demo, I found myself naturally refactoring the code as I went. It was such a pleasant experience discovering a new pattern and then cleaning up tech debt incrementally.

But after a while I noticed that I had something similar to an MVC pattern emerging in how I was structuring the code.

I recalled hearing [Carson Gross](https://bigsky.software/cv/) the creator of HTMX talking about this pattern, so figured I would rename the modules, and commit to testing this out. So far it has been working nicely.

The main components are:

- **Models** are the data structures and logic without any dependencies. These modules are where the "business logic" of my application is implemented.
- **Views** are pure functions and helpers to render data structures (such as defiend in the Models) to HTML.
- **Controllers** define and handle the routes for HTTP requests. Things like parsing URL query parameters or form submissions, making SQL queries to the DB, and handling invalid requests happen in these modules.

# [The BigTask Controller](#bigtask-controller) {#bigtask-controller}

I defined a top level function `respond` to take a `Request` along with additional parameters.

```roc
# src/Controllers/BigTask.roc
respond : {
    req : Request,
    urlSegments : List Str,
    dbPath : Str,
    session : Session,
} -> Task Response _
```

In `main.roc` this is called to handle all of the requests that start with the url segment `/bigTask`. This separated out all of the BigTask logic into a separate module which is easier to manage and hopefully in future will be easier to test.

```roc
# main.roc
# handle all requests for url segments starting with "/bigTask"
# e.g. GET, PUT, POST, DELETE /bigTask
(_, ["bigTask", ..]) ->
    Controllers.BigTask.respond {
        req,
        urlSegments : List.dropFirst urlSegments 1,
        dbPath,
        session,
    }
```

You can see here that the `respond` handler is passed it's dependencies, including the url segments, path to the SQLite3 database, and the current session parsed from request headers.

Another reason I separated this out into a module is that I wanted to test the idea of "protecting" the routes. I figured I would have the BigTask routes only available to authenticated users and if someone is a `Guest` then they shouldn't be able to access this information.

One advantage of having our logic managed in the server (as opposed to in a client side application) is that it is much easier to verify the user is authenticated. The session is managed in our DB, and so we can confirm the user has previously authenticated.

```roc
# src/Models/Session.roc
isAuthenticated : [Guest, LoggedIn Str] -> Result {} [Unauthorized]
isAuthenticated = \user ->
    if user == Guest then
        Err Unauthorized
    else
        Ok {}
```

The function `isAuthenticated` will take the user, and if they are a `Guest` return an `Err Unauthorized`. In our controller we pipe this into `Task.fromResult!` which will short-circuit our respond handler.

```roc
# src/Controllers/BigTask.roc
# confirm the user is Authenticated, these routes are all protected
Models.Session.isAuthenticated session.user |> Task.fromResult!

# ... continue with other BigTask routes
# that cannot be reached if the user is a Guest
```

The `Err Unauthorized` is then caught in our top-level error handler and transformed into a unauthorized HTML page response.

```roc
main : Request -> Task Response []
main = \req -> Task.onErr (handleReq req) \err ->
    when err is

        # ... other error cases like BadRequest, NotFound, etc.

        Unauthorized ->
            import Views.Unauthorised
            Views.Unauthorised.page {} |> respondHtml []
```

# [GET '/'—List BigTasks ](#bigtask-list) {#bigtask-list}

The first route on our BigTask controller returns our data table.

We start by parsing all of the relevant query parameters from the URL so we can use them to filter, sort, and paginate the data.

```roc
# src/Controllers/BigTask.roc

# parse the query parameters from the URL
queryParams =
    req.url
    |> parseQueryParams
    |> Result.withDefault (Dict.empty {})

# First check for the updateItemsPerPage form value,
# if not present then check for the items URL parameter,
# if not provided default to 25
items =
    queryParams
    |> Dict.get "updateItemsPerPage"
    |> Result.try Str.toI64
    |> Result.onErr \_ ->
        queryParams
        |> Dict.get "items"
        |> Result.try Str.toI64
    |> Result.withDefault 25

# parse the page number from the URL, default to 1
page =
    queryParams
    |> Dict.get "page"
    |> Result.try Str.toI64
    |> Result.withDefault 1

# parse the sortBy parameter from the URL, default to "ID"
sortBy =
    queryParams
    |> Dict.get "sortBy"
    |> Result.withDefault "ID"

# parse the sortDirection parameter from the URL, default to ASCENDING
# we parse either UPPER or lower case variations
sortDirection =
    when Dict.get queryParams "sortDirection" is
        Ok "asc" -> ASCENDING
        Ok "ASC" -> ASCENDING
        Ok "desc" -> DESCENDING
        Ok "DESC" -> DESCENDING
        _ -> ASCENDING
```

Then we query the SQLite3 database.

```roc
# query the database, for a page of data filtered and sorted
tasks = Sql.BigTask.list! {
    dbPath,
    page,
    items,
    sortBy,
    sortDirection,
}

# query the database for the total number of tasks
total = Sql.BigTask.total! { dbPath }
```

Finally we render a HTML table and add a response header to push a new URL.

```roc
sortDirectionStr =
    when sortDirection is
        ASCENDING -> "asc"
        DESCENDING -> "desc"

# update the URL with the current page, items per page, sort by, and sort direction that was parsed from earlier
updateURL = "/bigTask?page=$(Num.toStr page)&items=$(Num.toStr items)&sortBy=$(sortBy)&sortDirection=$(sortDirectionStr)"

# render the HTML table
Views.BigTask.page {
    session,
    tasks,
    sortBy,
    sortDirection,
    pagination : {
        page,
        items,
        total,
        baseHref: "/bigTask?",
    },
}
|> respondHtml [{name : "HX-Push-Url", value : Str.toUtf8 updateURL}]
```

# [Views.BigTask.page](#render-page) {#render-page}

This is what it looks like when rendered:

<img class="demo-img" src="/roc-htmx-demo-3/table-1.png" alt="screen capture of the rendered data table"/>

```roc
# src/Views/BigTask.roc
page = \{ session, tasks, pagination, sortBy, sortDirection } ->

    # we use a common layout helper for all pages e.g. navigation bar
    Views.Layout.layout
        {
            user: session.user,
            description: "Just making a big table",
            title: "BigTask",
            navLinks: Models.NavLinks.navLinks "BigTask",
        }
        [
            div [class "container-fluid"] [
                div [class "row align-items-center justify-content-center"] [
                    Html.h1 [] [Html.text "Big Task Table"],
                    Html.p [] [text "This table is big and has many tasks, each task is a big task..."],
                ],
                div [class "row"] [
                    div [class "inline-block m-2"] [

                        # a button to download the data as a CSV
                        # note we need to use a link with hx-disable to prevent
                        # htmx from intercepting the response and preventing the browser from downloading the file
                        a [
                            type "button",
                            class "btn btn-success",
                            href "/bigTask/downloadCsv",
                            (attribute "download") "",
                            (attribute "hx-disable") "",
                            (attribute "aria-label") "Download Button",
                        ] [
                            text "Download CSV",
                        ],
                    ],
                ],
                div [class "row"] [

                    # render the data table from a description of the columns and the tasks data rows
                    Views.Bootstrap.renderDataTable (columns { sortBy, sortDirection }) tasks
                ],
                div [class "row"] [

                    # render a pagination view with buttons to navigate the table
                    paginationView {
                        page: pagination.page,
                        items: pagination.items,
                        total: pagination.total,
                        baseHref: pagination.baseHref,
                        rowCount: Num.toU64 (tasks |> List.map (\_ -> 1) |> List.sum),
                        startRow: Num.toU64 (((pagination.page - 1) * pagination.items) + 1),
                    },
                ],
            ],
        ]
```

# [Data Table Inputs](#data-table-input) {#data-table-input}

How each cell in the data table is rendered is determined by a description of the column. For our table we created a helper and provide the `sortBy` and `sortDirection` values to vary the description for our sorted column.

```roc
columns :
    {
        sortBy : Str,
        sortDirection : [ASCENDING, DESCENDING],
    }
    -> List (DataTableColumn BigTask)
```

For example the first column `"Reference ID"` is the most simple, it simply displays the `referenceId` field of the task, and does not display a sorting icon, and it's width is not specified.

The `renderValueFn` takes a row of data (a single BigTask in this case) and returns a `Html.Node` that will be rendered in the table cell. Because we have provided the type annotation `List (DataTableColumn BigTask)` the compiler can verify that we are correctly using the `task` and provided helpful error messages.

```roc
{
    label: "Reference ID",
    name: "ReferenceID",
    sorted: None,
    renderValueFn: \task -> Html.text task.referenceId,
    width: None,
}
```

The second column `"Customer ID"` is more complex, it displays a `DataTableForm` input element to modify the `customerReferenceId` field of the task. It also displays a sorting icon button to toggle sorting the table by this column.

```roc
{
    label: "Customer ID",
    name: "CustomerReferenceID",
    sorted: sortedArg "CustomerReferenceID",
    renderValueFn: \task ->
        idStr = Num.toStr task.id
        {
            updateUrl: "/bigTask/customerId/$(idStr)",
            inputs: [
                {
                    name: "CustomerReferenceID",
                    id: "customer-id-$(idStr)",
                    value: Text task.customerReferenceId,
                    validation: None,
                },
            ],
        }
        |> Views.Bootstrap.newDataTableForm
        |> Views.Bootstrap.renderDataTableForm,
    width: None,
}
```

# [Views.Bootstrap.renderDataTable](#render-data-table) {#render-data-table}


# [Input Validaiton](#validation) {#validation}

<div class="container">
  <img class="demo-img" src="/roc-htmx-demo-3/table-3.png" alt="screen capture of a valid form"/>
  <img class="demo-img" src="/roc-htmx-demo-3/table-2.png" alt="screen capture of an invalid form"/>
</div>
