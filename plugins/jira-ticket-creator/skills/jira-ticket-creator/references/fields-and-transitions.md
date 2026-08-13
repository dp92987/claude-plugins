# Поля, статусы, спринты (проект PX, aviasales.atlassian.net)

Значения ниже сняты с живого проекта 13.08.2026. Если Jira отвечает «field
cannot be set», перечитай метаданные экрана создания через
`getJiraIssueTypeMetaWithFields` с `requiredFieldsOnly: false` — набор полей
меняется администратором, а не этим файлом.

`cloudId` = `b7cc35a5-077d-4e65-890a-2134bf111631` (сайт `aviasales.atlassian.net`,
проект `PX` = «Passenger Experience», id `12416`).

## Типы задач

| Тип | id | Для чего |
| --- | --- | --- |
| `Task` | 3 | умолчание для любой работы |
| `Bug` | 1 | дефект |
| `Story` | 10001 | постановка, которую дальше режут на задачи |
| `Epic` | 10000 | уровень выше задачи (`hierarchyLevel: 1`) |
| `Design` | 10363 | дизайн |
| `QA` | 12129 | приёмка, тестирование, документация, запуск |
| `Research` | 10230 | исследование |

`createJiraIssue` принимает имя типа (`issueTypeName`), id нужен только при
запросах метаданных.

## Кастомные поля

| Поле | id | Значение при создании |
| --- | --- | --- |
| Story Points | `customfield_10004` | число: 1, 2, 3, 5, 8 |
| Sprint | `customfield_10006` | id спринта числом |
| Epic Link | `customfield_10007` | ключ эпика строкой (`"PX-3480"`) |
| Parent | `parent` | ключ эпика (отдельный параметр `createJiraIssue`) |

**Эпик.** Передавай `parent` при создании. У существующих тикетов заполнены оба
поля (`parent` и Epic Link с одним и тем же ключом) — Jira синхронизирует их
сама. Если после создания `getJiraIssue` показывает пустой `parent`, проставь
Epic Link вручную:

```json
{"issueIdOrKey": "PX-XXXX", "fields": {"customfield_10007": "PX-3480"}}
```

## Компоненты

`Android`, `Backend`, `Backend Sharp`, `Design`, `iOS`, `Launch`, `QA`,
`QA_Android`, `QA_iOS`, `WEB`. Передаются массивом объектов:
`{"components": [{"name": "Backend"}]}`.

## Приоритеты

`Highest (P0)`, `High (P1)`, `Medium (P2)`, `Low (P3)`, `Lowest (P4)`. Без явной
просьбы не ставится — Jira подставляет `Medium (P2)`.

## Статусы и транзишены

Порядок жизни тикета:

```
Inbox → To Do → In Progress → Code Review → Ready to Merge/Deploy → Done
```

`Inbox` (id 12157) — статус создания, ничего делать не нужно.

`Closed` означает **отменённую** задачу. Для завершённой работы это `Done`.
Никогда не закрывай тикет вместо перевода в `Done`.

Прыгнуть в дальний статус нельзя — доска ведёт по цепочке. Известные id
транзишенов: `to To Do` 91, `to In Progress` 11, `to Review` 21,
`to Deploy` 151, `to Done` 141. Проверяй их через
`getTransitionsForJiraIssue` перед каждым шагом: доступный набор зависит от
текущего статуса.

Транзишен `to In Progress` автоматически назначает assignee на текущего
пользователя. Если тикет должен остаться неназначенным, не двигай его дальше
`To Do`.

## Спринты

`customfield_10006`, доска PX — id 420. В метаданных экрана создания список
спринтов пустой, поэтому id активного спринта берётся поиском:

```
searchJiraIssuesUsingJql:
  jql: "project = PX AND sprint in openSprints() ORDER BY updated DESC"
  fields: ["customfield_10006"]
  maxResults: 5
```

В ответе `customfield_10006` — массив объектов со `id`, `name`, `state`
(`active` или `future`), `startDate`, `endDate`. Пример живого значения:
`{"id": 29280, "name": "PX Sprint 08.12 — 08.25", "state": "active"}`.

- «в спринт», «в текущий спринт» → спринт со `state: "active"`.
- «в следующий спринт» → `sprint in futureSprints()`, ближайший по `startDate`.
  Если будущего спринта нет, **спроси пользователя**, что делать: положить в
  активный, оставить в бэклоге или подождать создания спринта. Сам спринт не
  создавай — это действие уровня доски, оно затрагивает всю команду.

Ставь спринт при создании: `{"customfield_10006": 29280}`. Если Jira отклоняет
поле на экране создания, проставь его после через `editJiraIssue` тем же
значением; при отказе на числе попробуй массив (`[29280]`).

## Assignee

Не назначается по умолчанию. Когда исполнитель назван, найди его accountId через
`lookupJiraAccountId` (по имени или почте) и передай в `assignee_account_id`.
Если поиск даёт несколько человек, покажи варианты и спроси — назначить не того
человека хуже, чем оставить поле пустым.

## Связь «split from»

Тип `Work item split` (id 10404): `inward` = «split from», `outward` =
«split to».

```json
{
  "type": "Work item split",
  "inwardIssue": "PX-4797",
  "outwardIssue": "PX-5505"
}
```

`inwardIssue` — стори-источник, `outwardIssue` — новая задача. Проверено на
существующей связи PX-5505 → PX-4797. Обратный порядок создаёт связь, которая
читается наоборот.

Другие полезные типы: `Blocks` («is blocked by» / «blocks»), `Relates`,
`Problem/Incident` («is caused by» / «causes»), `Duplicate`.

## Проверка результата

После создания и всех досозданий:

```
getJiraIssue с fields:
  ["summary","status","issuetype","labels","components","parent",
   "customfield_10004","customfield_10006","issuelinks","assignee"]
```

Сверь с тем, что было в превью, и назови расхождения пользователю.

## Если запрос падает

- **Cloudflare-страница «Attention Required!» вместо JSON.** WAF перед MCP-эндпоинтом
  реагирует на код в теле запроса (curl, mongosh, JSON). Это подтверждено на
  Confluence; на описании тикета с большим блоком кода возможно то же. Обходной
  путь: заэкранировать код HTML-сущностями (`<` → `&lt;`) и повторить вызов.
- **MCP не подключён** (headless- или cron-запуск: MCP с интерактивной
  авторизацией там может отсутствовать). Не молчи и не имитируй успех — отдай
  пользователю готовый заголовок и описание, чтобы он создал тикет руками.
