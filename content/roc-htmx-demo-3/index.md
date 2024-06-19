[Return to Home](/)

# Fullstack Roc + htmx—Data Table

<time class="post-date" datetime="2024-06-19">19 Jun 2024</time> *~15 mins reading time*

- [Demonstration](#demo)
- [Refactor into Model-View-Controller](#mvc)
- [The BigTask Controller](#bigtask-controller)
- [Protecting Routes](#protecting-routes)
- [GET '/'—List BigTasks](#bigtask-list)
- [Views.BigTask.page](#render-page)
- [Data Table Inputs](#data-table-input)
- [Views.Bootstrap.renderDataTable](#render-data-table)
- [PUT '/customerID/<id>'—Update CustomerReferenceID](#put-update-data)
- [Form Input Validaiton](#validation)
- [Download CSV Data](#download-csv)
- [Client-side State Management](#client-state)
- [Final thoughts](#final-thoughts)

In this article, I continue experimenting with [lukewilliamboswell/roc-htmx-playground](https://github.com/lukewilliamboswell/roc-htmx-playground/) and build a Data Table. The inspiration for this comes from the idea of having a table in an SQL database and wanting a simple way to display and edit this using fullstack roc + htmx.

There were a few things I wanted to explore with this including; making individual columns sortable, pagination, filtering the table results, and making a download button to get the data as a CSV.

In summary, I have been very pleased with the experience writing this demo, and I am convinced this will be a great way to build larger web applications in the future.

Here is a demonstration of the data table in action.

## [Demonstration](#demo) {#demo}

Code for this article is available at [this commit](https://github.com/lukewilliamboswell/roc-htmx-playground/tree/18c94a7afa1e10767c209c5e1b7538ce31eca12d).

<img class="demo-img" src="/roc-htmx-demo-3/demo.gif" alt="screen capture of the application being used"/>

## [Refactor into Model-View-Controller](#mvc) {#mvc}

While writing the code for this demo, I found myself naturally refactoring as I went. It was such a pleasant experience discovering a new pattern and incrementally cleaning up tech debt.

After several changes, I noticed an MVC pattern emerging in how I was structuring the code. I recall hearing [Carson Gross](https://bigsky.software/cv/) the creator of HTMX talking about this pattern from a podcast, so figured I would rename the modules, and commit to testing this out. So far it has been working nicely and I haven't found any issues working with roc modules.

The main components are:

- **Models** are the data structures and logic without any dependencies. These modules are where the "business logic" of my application is implemented.
- **Views** are pure functions and helpers to render data structures (such as defined in the Models) to HTML.
- **Controllers** define and handle the routes for HTTP requests. Things like parsing URL query parameters or form submissions, making SQL queries to the DB, and handling invalid requests happen in these modules.

## [The BigTask Controller](#bigtask-controller) {#bigtask-controller}

The BigTask controller is a top-level function that takes a `Request` along with additional parameters.

```roc
# src/Controllers/BigTask.roc
respond : {
    req : Request,
    urlSegments : List Str,
    dbPath : Str,
    session : Session,
} -> Task Response _
```

This is called in `main.roc` to handle all of the requests that start with the url segment `/bigTask`.

```roc
# main.roc

(_, ["bigTask", ..]) ->
    Controllers.BigTask.respond {
        req,
        urlSegments : List.dropFirst urlSegments 1,
        dbPath,
        session,
    }
```

## [Protecting Routes](#protecting-routes) {#protecting-routes}

I wanted to test the idea of how to "protect" some routes, so they are only available to authenticated users. If someone is a `Guest` they shouldn't be able to access sensitive information. Instead, the server should respond appropriately with an error message.

All of our app logic is managed in the server (as opposed to in a client-side application), so it is much easier to verify the user is authenticated. The session is managed in the database, so we can confirm the user has previously authenticated using a simple helper function.

```roc
# src/Models/Session.roc
isAuthenticated : [Guest, LoggedIn Str] -> Result {} [Unauthorized]
isAuthenticated = \user ->
    if user == Guest then
        Err Unauthorized
    else
        Ok {}
```

The function `isAuthenticated` will take the user, and if they are a `Guest` return an `Err Unauthorized`. In our controller, we pipe this into `Task.fromResult!` which will short-circuit to our top-level handler.

```roc
Models.Session.isAuthenticated session.user |> Task.fromResult!

# ... continue to handle sensitive routes
```

Any `Err Unauthorized` will be caught in our top-level error handler and transformed into an unauthorized HTML page response.

```roc
main : Request -> Task Response []
main = \req -> Task.onErr (handleReq req) \err ->
    when err is
        Unauthorized ->
            Views.Unauthorised.page {} |> respondHtml []

        # ... handle other errors like BadRequest, NotFound, etc.
```

## [GET '/'—List BigTasks](#bigtask-list) {#bigtask-list}

The first route on our BigTask controller returns our data table.

We start by parsing all of the relevant query parameters from the URL so we can use them to filter, sort, and paginate the data.

```roc
# src/Controllers/BigTask.roc

queryParams =
    req.url
    |> parseQueryParams
    |> Result.withDefault (Dict.empty {})

items =
    queryParams
    |> Dict.get "updateItemsPerPage"
    |> Result.try Str.toI64
    |> Result.onErr \_ ->
        queryParams
        |> Dict.get "items"
        |> Result.try Str.toI64
    |> Result.withDefault 25

page =
    queryParams
    |> Dict.get "page"
    |> Result.try Str.toI64
    |> Result.withDefault 1

sortBy =
    queryParams
    |> Dict.get "sortBy"
    |> Result.withDefault "ID"

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
tasks = Sql.BigTask.list! {
    dbPath,
    page,
    items,
    sortBy,
    sortDirection,
}

total = Sql.BigTask.total! { dbPath }
```

Finally, we render a HTML table and add a response header to push a new URL. The URL will include the current page, items per page, sort by, and sort direction that was parsed earlier.

```roc
sortDirectionStr =
    when sortDirection is
        ASCENDING -> "asc"
        DESCENDING -> "desc"

updateURL = "/bigTask?page=$(Num.toStr page)&items=$(Num.toStr items)&sortBy=$(sortBy)&sortDirection=$(sortDirectionStr)"

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

## [Views.BigTask.page](#render-page) {#render-page}

This is what it looks like when rendered:

<img class="demo-img" src="/roc-htmx-demo-3/table-1.png" alt="screen capture of the rendered data table"/>

```roc
# src/Views/BigTask.roc

page = \{ session, tasks, pagination, sortBy, sortDirection } ->
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

                    # render the data table from a description of the columns and the tasks
                    Views.Bootstrap.renderDataTable (columns { sortBy, sortDirection }) tasks
                ],
                div [class "row"] [

                    # render pagination buttons to navigate the table
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

The following is our download button. We use a link with `hx-disable` to prevent htmx from intercepting the response which would stop the browser from downloading the file.

```roc
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
```

## [Data Table Inputs](#data-table-input) {#data-table-input}

How each cell in the data table is rendered is determined by a description of the column. For our table, we created a helper and provided the `sortBy` and `sortDirection` values to vary the description for our sorted column.

```roc
columns :
    {
        sortBy : Str,
        sortDirection : [ASCENDING, DESCENDING],
    }
    -> List (DataTableColumn BigTask)
```

For example the first column `"Reference ID"` is the most simple, it displays the `referenceId` field of the task, does not display a sorting icon, and its width is not specified.

```roc
{
    label: "Reference ID",
    name: "ReferenceID",
    sorted: None,
    renderValueFn: \task -> Html.text task.referenceId,
    width: None,
}
```

The `renderValueFn` takes a row of data (a BigTask) and returns a `Html.Node` to display as a single cell in the table. Because we have provided the type annotation `List (DataTableColumn BigTask)` the compiler can verify that we are correctly using the `task` and provide helpful error messages.

The second column `"Customer ID"` is more complex, it displays a `DataTableForm` input element to modify the `customerReferenceId` field of the task. It also displays a sorting icon button to toggle sorting the table by this column.

```roc
{
    label: "Customer ID",
    name: "CustomerReferenceID",
    sorted: sortedArg "CustomerReferenceID",
    width: None,
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
}
```

## [Views.Bootstrap.renderDataTable](#render-data-table) {#render-data-table}

The `DataTableForm` type is used to render a form with inputs such as text box, date picker, or dropdown selection.

```roc
# src/Views/Bootstrap.roc

DataTableInputValidation : [None, Valid, Invalid Str]
DataTableForm := {
    updateUrl : Str,
    inputs : List {
        name : Str, # the key in form data
        id : Str, # uniquely identifier, maintain focus between renders
        value : [Text Str, Date Str, Choice {selected: U64, options: List Str}],
        validation : DataTableInputValidation,
    },
}
```

```roc
newDataTableForm = @DataTableForm

renderDataTableForm : DataTableForm -> Html.Node
renderDataTableForm = \@DataTableForm {updateUrl, inputs} ->

    renderFormSection = \{name,id,value,validation} ->
        when value is
            Text str -> renderTextSection {name,id,str,validation}
            Date str -> renderDateSection {name,id,str,validation}
            Choice {selected, options} -> renderChoiceSection {name,id,selected,options,validation}

    Html.form [
        (attribute "hx-put") updateUrl,
        (attribute "hx-trigger") "input delay:250ms",
        (attribute "hx-swap") "outerHTML",
    ] (
        inputs
        |> List.map renderFormSection
        |> List.join
    )

renderTextSection = \{name,id,str,validation} ->
    [
        Html.label [Attribute.for id, Attribute.hidden ""] [Html.text name],
        (Html.element "input") [
            Attribute.type "text",
            class "form-control $(validationClass validation)",
            Attribute.id id,
            Attribute.name name,
            Attribute.value str,
        ] [],
        validationMsg validation
    ]
```

## [PUT '/customerID/<id>'—Update CustomerReferenceID](#put-update-data) {#put-update-data}

The following shows how we handle an update to the `CustomerReferenceID` for a given task. We decode the request body and parse the expected fields.

```roc
# src/Controllers/BigTask.roc

(Put, ["customerId", idStr]) ->

    values = decodeFormValues! req.body

    id = decodeBigTaskId! idStr # either return a I64 or short circuit with a BadRequest

    validation =
        Dict.get values "CustomerReferenceID"
        |> Result.mapErr \_ -> BadRequest (MissingField "CustomerReferenceID")
        |> Result.try \cridstr ->
            when Str.toI64 cridstr is
                Ok i64 if i64 > 0 && i64 < 100000 -> Ok Valid
                _ -> Ok (Invalid "must be a number between 0 and 100,000")
        |> Task.fromResult!

    updateBigTaskOnlyIfValid! validation {dbPath, id, values}

    {
        updateUrl : "/bigTask/customerId/$(idStr)",
        inputs : [{
            name : "CustomerReferenceID",
            id : "customer-id-$(idStr)",
            value : Text (Dict.get values "CustomerReferenceID" |> Result.withDefault ""),
            validation,
        }],
    }
    |> Views.Bootstrap.newDataTableForm
    |> Views.Bootstrap.renderDataTableForm
    |> respondHtml []

decodeBigTaskId = \idStr ->
    Str.toI64 idStr
    |> Result.mapErr \_ -> BadRequest (InvalidBigTaskID idStr "expected a valid 64-bit integer")
    |> Task.fromResult
```

## [Form Input Validaiton](#validation) {#validation}

The response from our `PUT` request will include the validation state of the input. This is a useful visual indicator to the user that their input is either Valid (displayed in green) and has been successfully saved, or it is Invalid (displayed in red with a message) and has not been saved to the database.

<div class="container">
  <img class="demo-img" src="/roc-htmx-demo-3/table-3.png" alt="screen capture of a valid form"/>
  <img class="demo-img" src="/roc-htmx-demo-3/table-2.png" alt="screen capture of an invalid form"/>
</div>

## [Download CSV Data](#download-csv) {#download-csv}

The following code example shows the endpoint we use to download the data as a CSV file.

When the server receives `GET` request to `/bigTask/downloadCsv`, it responds with our data in the response body; the content type, disposition, and length headers.

```roc
(Get, ["downloadCsv"]) ->

    data =
        """
        ID, CustomerReferenceID, DateCreated, Status
        1, 12345, 2021-01-01, Raised
        2, 67890, 2021-01-02, Completed
        3, 54321, 2021-01-03, Deferred
        """
        |> Str.toUtf8

    Task.ok {
        status: 200,
        headers: [
            { name: "Content-Type", value: Str.toUtf8 "text/plain" },
            { name: "Content-Disposition", value: Str.toUtf8 "attachment; filename=table.csv" },
            { name: "Content-Length", value: Str.toUtf8 "$(List.len data |> Num.toStr)" },
        ],
        body: data,
    }
```

In this example, we hard-coded the CSV data. A more realistic example might query the database, and use an encoder to convert to the desired format. For example, `Encode.toBytes tasks Json.utf8` would encode the list of tasks as JSON data.

## [Client-side State Management](#client-state) {#client-state}

The state of the BigTask table is managed using URL query parameters.

For example, the following URL encodes the current page number, the number of items per page, and which column and direction to sort by.

```
/bigTask?page=1&items=5&sortBy=ID&sortDirection=asc
```

Keeping the state for our table in the URL has some nice advantages.

First, navigating to the same URL provides the same view.

Second, any changes can be saved in browser history which means the "Back" and "Forward" buttons navigate through the state and work as expected.

To achieve this there were a couple of features of htmx and the browser used. Both of these can be seen in the example below.

```roc
Html.form [
    (attribute "hx-get") "", # reload the current URL, including the curent parameters
    (attribute "hx-trigger") "input delay:500ms",
    (attribute "hx-target") "body",
    (attribute "hx-swap") "outerHTML",
    (attribute "id") "formUpdateItemsPerPage",
] [
    (element "input") [
        Attribute.type "number",
        Attribute.name "updateItemsPerPage",
        class "form-control",
        (attribute "id") "updateItemsPerPage",
        Attribute.value "$(Num.toStr currItemsPerPage)",
        Attribute.min "$(Num.toStr minItemsPerPage)",
        Attribute.max "$(Num.toStr maxItemsPerPage)",
        styles [
            "border-top-right-radius: 5px;",
            "border-bottom-right-radius: 5px;",
        ],
    ] []
],
```

The form is submitted using the `hx-get` attribute with an empty URL `""`. This is a standard browser behaviour to reference the current document and so htmx will send its query using the current URL and parameters along with the form values.

The form includes the value `updateItemsPerPage` which instructs our server to update the number of items per page.

As we saw earlier, when we query for the table; first we parse this value from the query parameters, and only if it is not present do we use the value of `items` or a default.

```roc
items =
    queryParams
    |> Dict.get "updateItemsPerPage"
    |> Result.try Str.toI64
    |> Result.onErr \_ ->
        queryParams
        |> Dict.get "items"
        |> Result.try Str.toI64
    |> Result.withDefault 25
```

## [Final thoughts](#final-thoughts) {#final-thoughts}

In this article, I've shared some of the things I learnt while building a data table using htmx and roc. I hope you find it useful and are inspired to try it out for yourself.

I look forward to future experiments with htmx and roc and hope to share more in the future.
