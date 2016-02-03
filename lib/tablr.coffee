_ = require 'underscore-plus'
{CompositeDisposable} = require 'atom'
[url, Range, Table, DisplayTable, TableEditor, TableElement, TableSelectionElement, CSVConfig, CSVEditor, CSVEditorElement] = []

module.exports =
  config:
    tableEditor:
      type: 'object'
      properties:
        undefinedDisplay:
          title: 'Undefined Value Display'
          description: 'How to render undefined values in a cell. Leave the field blank to display an empty cell.'
          type: 'string'
          default: ''
        pageMoveRowAmount:
          title: 'Page Move Row Amount'
          description: 'The number of rows to jump when using the `core:page-up` and `core:page-down` commands.'
          type: 'integer'
          default: 20
        pageMoveColumnAmount:
          title: 'Page Move Column Amount'
          description: 'The number of columns to jump when using the `tablr:page-left` and `tablr:page-right` commands.'
          type: 'integer'
          default: 5
        scrollSpeedDuringDrag:
          title: 'Scroll Speed During Drag'
          description: 'The speed of the scrolling motion during a drag gesture, in pixels.'
          type: 'integer'
          default: 20
        scrollPastEnd:
          title: 'Scroll Past End'
          description: 'When enabled, the table can scroll past the end of the table both vertically and horizontally to let manipulate rows and columns more easily.'
          type: 'boolean'
          default: false

        rowHeight:
          title: 'Row Height'
          description: 'The default row height in pixels.'
          type: 'integer'
          default: 24
        rowOverdraw:
          description: 'The number of rows to render outside the bounds of the visible area to smooth the scrolling motion.'
          title: 'Row Overdraw'
          type: 'integer'
          default: 3
        minimumRowHeight:
          title: 'Minimum Row Height'
          description: 'The minimum height of a row in pixels.'
          type: 'integer'
          default: 16
        rowHeightIncrement:
          title: 'Row Height Increment'
          description: 'The amount of pixels to add or remove to a row when using the row resizing commands.'
          type: 'integer'
          default: 20

        columnWidth:
          title: 'Column Width'
          description: 'The default column width in pixels.'
          type: 'integer'
          default: 120
        columnOverdraw:
          title: 'Column Overdraw'
          description: 'The number of columns to render outside the bounds of the visible area to smooth the scrolling motion.'
          type: 'integer'
          default: 2
        minimumColumnWidth:
          title: 'Minimum Column Width'
          description: 'The minimum column width in pixels.'
          type: 'integer'
          default: 40
        columnWidthIncrement:
          title: 'Column Width Increment'
          description: 'The amount of pixels to add or remove to a column when using the column resizing commands.'
          type: 'integer'
          default: 20

    copyPaste:
      type: 'object'
      properties:
        flattenBufferMultiSelectionOnPaste:
          title: 'Flatten Buffer Multi Selection On Paste'
          type: 'boolean'
          default: false
          description: 'If the clipboard content comes from a multiple selection copy in a text editor, the whole clipboard text will be pasted in each cell of the table selection.'
        distributeBufferMultiSelectionOnPaste:
          title: 'Distribute Buffer Multi Selection On Paste'
          type: 'string'
          default: 'vertically'
          enum: ['horizontally', 'vertically']
          description: 'If the clipboard content comes from a multiple selection copy in a text editor, each selection will be considered as part of the same column (`vertically`) or of the same row (`horizontally`).'
        treatEachCellAsASelectionWhenPastingToABuffer:
          title: 'Treat Each Cell As A Selection When Pasting To A Buffer'
          type: 'boolean'
          default: true
          description: 'When copying from a table to paste the content in a text editor this setting will make each cell appear as if they were created from different selections.'

    csvEditor:
      type: 'object'
      properties:
        columnDelimiter:
          title: 'Default Column Delimiter'
          type: 'string'
          default: ','
        rowDelimiter:
          title: 'Default Row Delimiter'
          type: 'string'
          default: 'auto'
        quote:
          title: 'Default Quote Character'
          type: 'string'
          default: '"'
        escape:
          title: 'Default Espace Character'
          type: 'string'
          default: '"'
        comment:
          title: 'Default Comment Character'
          type: 'string'
          default: '#'

    supportedCsvExtensions:
      type: 'array'
      default: ['csv', 'tsv']
      description: 'The extensions for which the CSV opener will be used.'
    defaultColumnNamingMethod:
      type: 'string'
      default: 'alphabetic'
      enum: ['alphabetic', 'numeric', 'numericZeroBased']
      description: 'When file has no header, select the default naming method for the columns. `alphabetic` means use A, B,…, Z, AA, AB… `numeric` is for simple numbers, ie 1, 2… `numericZeroBased` is similar to `numeric`, except that it starts numbering from 0 instead of 1'


  activate: ({csvConfig}) ->
    @csvConfig = new CSVConfig(csvConfig)

    @subscriptions = new CompositeDisposable
    if atom.inDevMode()
      @subscriptions.add atom.commands.add 'atom-workspace',
        'tablr:demo-large': => atom.workspace.open('tablr://large')
        'tablr:demo-small': => atom.workspace.open('tablr://small')

    @subscriptions.add atom.commands.add 'atom-workspace',
      'tablr:clear-csv-storage': => @csvConfig.clear()
      'tablr:clear-csv-choice': => @csvConfig.clearOption('choice')
      'tablr:clear-csv-layout': => @csvConfig.clearOption('layout')

    @subscriptions.add atom.workspace.addOpener (uriToOpen) =>
      return unless ///\.#{atom.config.get('tablr.supportedCsvExtensions').join('|')}$///.test uriToOpen

      choice = @csvConfig.get(uriToOpen, 'choice')
      options = _.clone(@csvConfig.get(uriToOpen, 'options') ? {})

      return atom.workspace.openTextFile(uriToOpen) if choice is 'TextEditor'

      new CSVEditor({filePath: uriToOpen, options, choice})

    @subscriptions.add atom.workspace.addOpener (uriToOpen) =>
      url ||= require 'url'

      {protocol, host} = url.parse uriToOpen
      return unless protocol is 'tablr:'

      switch host
        when 'large' then @getLargeTable()
        when 'small' then @getSmallTable()

    @subscriptions.add atom.contextMenu.add
      'tablr-editor': [{
        label: 'Tablr'
        created: (event) ->
          {pageX, pageY, target} = event
          return unless target.getScreenColumnIndexAtPixelPosition? and target.getScreenRowIndexAtPixelPosition?

          contextMenuColumn = target.getScreenColumnIndexAtPixelPosition(pageX)
          contextMenuRow = target.getScreenRowIndexAtPixelPosition(pageY)

          @submenu = []

          if contextMenuRow? and contextMenuRow >= 0
            target.contextMenuRow = contextMenuRow

            @submenu.push {label: 'Fit Row Height To Content', command: 'tablr:fit-row-to-content'}

          if contextMenuColumn? and contextMenuColumn >= 0
            target.contextMenuColumn = contextMenuColumn

            @submenu.push {label: 'Fit Column Width To Content', command: 'tablr:fit-column-to-content'}
            @submenu.push {type: 'separator'}
            @submenu.push {label: 'Align left', command: 'tablr:align-left'}
            @submenu.push {label: 'Align center', command: 'tablr:align-center'}
            @submenu.push {label: 'Align right', command: 'tablr:align-right'}

          setTimeout ->
            delete target.contextMenuColumn
            delete target.contextMenuRow
          , 10
      }]

  deactivate: ->
    @subscriptions.dispose()

  provideTablrModelsServiceV1: ->
    {Table, DisplayTable, TableEditor, Range}

  getSmallTable: ->
    table = new TableEditor

    table.lockModifiedStatus()
    table.addColumn 'key', width: 150, align: 'right'
    table.addColumn 'value', width: 150, align: 'center'
    table.addColumn 'locked', width: 150, align: 'left'

    rows = []
    for i in [0...100]
      rows.push [
        "row#{i}"
        Math.random() * 100
        if i % 2 is 0 then 'yes' else 'no'
      ]

    table.addRows(rows)

    table.clearUndoStack()
    table.initializeAfterSetup()
    table.unlockModifiedStatus()
    return table

  getLargeTable: ->
    table = new TableEditor

    table.lockModifiedStatus()
    table.addColumn 'key', width: 150, align: 'right'
    table.addColumn 'value', width: 150, align: 'center'
    for i in [0..100]
      table.addColumn undefined, width: 150, align: 'left'

    rows = []
    for i in [0...1000]
      data = [
        "row#{i}"
        Math.random() * 100
      ]
      for j in [0..100]
        if j % 2 is 0
          data.push if i % 2 is 0 then 'yes' else 'no'
        else
          data.push Math.random() * 100

      rows.push data

    table.addRows(rows)

    table.clearUndoStack()
    table.initializeAfterSetup()
    table.unlockModifiedStatus()

    return table

  serialize: ->
    csvConfig: @csvConfig.serialize()

  loadModelsAndRegisterViews: ->
    Range = require './range'
    Table = require './table'
    DisplayTable = require './display-table'
    TableEditor = require './table-editor'
    TableElement = require './table-element'
    TableSelectionElement = require './table-selection-element'
    CSVConfig = require './csv-config'
    CSVEditor = require './csv-editor'
    CSVEditorElement = require './csv-editor-element'

    CSVEditorElement.registerViewProvider()
    TableElement.registerViewProvider()
    TableSelectionElement.registerViewProvider()

    atom.deserializers.add(CSVEditor)
    atom.deserializers.add(TableEditor)
    atom.deserializers.add(DisplayTable)
    atom.deserializers.add(Table)

module.exports.loadModelsAndRegisterViews()
