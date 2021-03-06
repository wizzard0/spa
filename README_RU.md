#SPA

**S** ingle **P** age **A** pplications сборщик и загрузчик приложений для работы в браузере в условиях оффлайн.

Основная идея сборщика в том что б вычислить зависимости между файлами-моделями в приложении javascript и вычислить корректный порядок загрузки который можно передать специальному загрузчику. Также можно определить список изменяемых файлов и проводить пофайловое обновление. Предпочтительным считается использование модулей в формате `CommonJS`.

Преимущества:

  - загружать модули асинхронно не нужно
  - не нужно явно писать обертки
  - в загрузчике меньше подвижных частей и промежуточных состояний
  - нету дублирования данных в кешах и возможных конфликтов
  - код загрузчика не смешан с кодом приложения
  - можно легко визуализировать процесс загрузки любым способом

## Запуск

Билдер настраивается конфигурационным файлом. Единственный параметр коммандной строки - путь к этому файлу. 

```
spa -c spa.yaml
```

## Настройка

Конфигурационный файл может иметь формат `yaml` или `json`. Он представляет собой словарь с со следующими возможными ключами.

**root** - путь к корневому каталогу в котором билдер будет искать файлы. Может задаваться как относительный путь от расположения самого конфигурационного файла.

**extensions** - список расширений файлов которые билдер будет рассматривать. По умолчанию равен `[".js"]`

**excludes** - список файлов и папок которые исключаются из области видимости сборщика. По умолчанию - пуст. Список можно задавать как правила в фомате `wildcard` или `glob`, например `./something/**/test/*.js`. Правила проверяют пути относительно корневого каталога.

**paths** - превдонимы путей для использования внутри загружаемого проекта. Имеет формат словаря в котором ключи - идентификаторы префиксов-псевдонимов, а значения - относительные пути от корневого каталога. Например:

```
root: "/testimonial/"
paths:
    vendor: "/lib/contrib"
```

С таким конфигом в файле `/testimonial/src/a.js` можно использовать модуль `/testimonial/lib/contrib/b.js` написав `require('vendor/b.js')`

**hosting** - словарь с правилами для преобразования относительных путей к файлам в их адреса URL. Ключи - правила, такие же как в `excludes`, в которых скобками можно выделять части пути; значения - формат URL в который подставляются выделеные части. Например:

```
hosting:
    "/lib/(**/*.js)": "http://myapp.com/$1"
```

Файл `/lib/app/main.js` будет загружаться из `http://myapp.com/app/main.js`.

**loaders** - словарь правил по которому определяется тип загрузчика модуля. Ключи - правила, такие же как в `excludes`; значения - типы моделей. Возможные значения типов: `cjs`, `amd`, `junk`, `raw`.

- _cjs_ - модуль имеет формат `CommonJS`
- _amd_ - модуль имеет формат `AMD` или `UMD`.
- _junk_ - модуль пытается модифицировать window.
- _raw_ - module пытается создавать локальные переменные, которые должны попасть в глобальный контекст.

**default_loader** - тип загрузчика для тех кто не подошли ни под какое правило. По умолчанию - `cjs`.

**manifest** - относительный путь к файлу манифеста загрузки. Если путь не указан, то файл не будет создан.

**pretty** - булевый флаг для более красивого содержимого файла `manifest`.

**index** - относительный путь к стартовому файлу приложения файлу. Загрузчик вместе со всеми необходимыми частями будет встроен в этот файл. Если путь не указан, то файл не будет создан.

**appcache** - относительный путь к `appcache` манифесту `html5`. Если путь не указан, то файл не будет создан.

**cached** - список путей к дополнительным файлам, которые должны быть внесены в `appcache`. Адреса для этих файлов вычисляются по правилам описанным в `hosting`.

**assets** - словарь путей к дополнительным файлам сборщика, которые могут быть кастомизированы для нужд приложения.

- appcache_template - путь к шаблону для генерации `appcache`. В шаблоне можно использовать список `cached`.
- index_template - путь к шаблону для генерации `index`. В шаблоне можно использовать имена из `assets`. Только не вставляйте шаблон сам в себя :)
- md5 - путь к сторонней библиотеке для генерации `md5`. Заменять не рекомендуется.
- loader - путь к заранее собранному коду загрузчика.
- fake_app - путь к коду стартового приложения, которое будет использоваться до того как первая версия клиентского приложения будет загружена.
- fake_manifest - путь к манифесту для стартового приложения.

Все пути могут быть относительными от текущей рабочей папки приложения.

## Пример

```yaml
root: "/testimonial/"
index: index.html
appcache: main.appcache
paths:
    vendor: "/lib/contrib"
assets:
    index_template: /assets/index.tmpl
    appcache_template: /assets/appcache.tmpl
    loader: /assets/loader.js
    md5: /assets/md5.js
    fake_app: /assets/fake/app.js
    fake_manifest: /assets/fake/manifest.json
cached:
    - /a.js
hosting:
    "/(**/*.*)": "http://127.0.0.1:8010/$1"
```