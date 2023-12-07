app "website"
    packages { pf: "../roc/examples/static-site-gen/platform/main.roc" }
    imports [
        pf.Html.{ Node, html, head, body, footer, main, text, link, meta },
        pf.Html.Attributes.{ content, name, id, href, rel, lang, class, charset },
    ]
    provides [transformFileContent] to pf

pageData =
    Dict.empty {}
    |> Dict.insert "index.html" { title: "Home", description: "" }

getPage : Str -> { title : Str, description : Str }
getPage = \current ->
    Dict.get pageData current
    |> Result.withDefault { title: "", description: "" }

getTitle : Str -> Str
getTitle = \current ->
    getPage current |> .title

getDescription : Str -> Str
getDescription = \current ->
    getPage current |> .description

transformFileContent : Str, Str -> Str
transformFileContent = \page, htmlContent ->
    Html.render (view page htmlContent)

view : Str, Str -> Html.Node
view = \page, htmlContent ->
    mainBody = [text htmlContent]

    bodyAttrs = [id "index-page"]

    html [lang "en", class "no-js"] [
        head [] [
            meta [charset "utf-8"],
            Html.title [] [text (getTitle page)],
            meta [name "description", content (getDescription page)],
            meta [name "viewport", content "width=device-width"],
            link [rel "stylesheet", href "/styles.css"],
        ],
        body bodyAttrs [
            main [] mainBody,
            footer [] [],
        ],
    ]
