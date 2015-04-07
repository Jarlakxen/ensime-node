{Subscriber} = require 'emissary'
{TooltipView} = require './tooltip-view'
{CompositeDisposable} = require 'atom'
$ = require 'jquery'
{isScalaSource, pixelPositionFromMouseEvent, screenPositionFromMouseEvent, getElementsByClass} = require './utils'


class EditorControl
  constructor: (@editor, @client) ->
    @disposables = new CompositeDisposable

    @editorView = atom.views.getView(@editor);

    @scroll = $(getElementsByClass(@editorView, '.scroll-view'))

    @subscriber = new Subscriber()

    @editor.onDidDestroy =>
      @deactivate()


    # buffer events for automatic check
    buffer = @editor.getBuffer()
    @disposables.add buffer.onDidSave () =>
      return unless isScalaSource @editor

      # TODO if uri was changed, then we have to remove all current markers
      workspaceElement = atom.views.getView(atom.workspace)
      # TODO: typecheck file on save
      #if atom.config.get('ensime.checkOnFileSave')
      #  atom.commands.dispatch workspaceElement, 'ensime:typecheck-file'

    @subscriber.subscribe @scroll, 'mousemove', (e) =>
      @clearExprTypeTimeout()
      @exprTypeTimeout = setTimeout (=>
        @showExpressionType e
      ), 100
    @subscriber.subscribe @scroll, 'mouseout', (e) =>
      @clearExprTypeTimeout()


  deactivate: ->
    @clearExprTypeTimeout()
    @subscriber.unsubscribe()
    @disposables.dispose()
    @editorView.control = undefined


  # helper function to hide tooltip and stop timeout
  clearExprTypeTimeout: ->
    if @exprTypeTimeout?
      clearTimeout @exprTypeTimeout
      @exprTypeTimeout = null
    @hideExpressionType()

  # get expression type under mouse cursor and show it
  showExpressionType: (e) ->
    return unless isScalaSource(@editor) and not @exprTypeTooltip?

    pixelPt = pixelPositionFromMouseEvent(@editor, e)
    screenPt = @editor.screenPositionForPixelPosition(pixelPt)
    bufferPt = @editor.bufferPositionForScreenPosition(screenPt)
    nextCharPixelPt = @editorView.pixelPositionForBufferPosition([bufferPt.row, bufferPt.column + 1])

    return if pixelPt.left >= nextCharPixelPt.left

    # find out show position
    offset = @editor.getLineHeightInPixels() * 0.7
    tooltipRect =
      left: e.clientX
      right: e.clientX
      top: e.clientY - offset
      bottom: e.clientY + offset

    # create tooltip with pending
    @exprTypeTooltip = new TooltipView(tooltipRect)


    textBuffer = @editor.getBuffer()
    offset = textBuffer.characterIndexForPosition(bufferPt)

    @client.sendAndThen("(swank:type-at-point \"#{@editor.getPath()}\" #{offset})", (msg) =>
      # (:return (:ok (:arrow-type nil :name "Ingredient" :type-id 3 :decl-as class :full-name "se.kostbevakningen.model.record.Ingredient" :type-args nil :members nil :pos (:type offset :file "/Users/viktor/dev/projects/kostbevakningen/src/main/scala/se/kostbevakningen/model/record/Ingredient.scala" :offset 545) :outer-type-id nil)) 3)
      fullName = msg[":ok"]?[":full-name"]
      console.log("EditorControl recieved msg from ensime: #{msg}. @exprTypeTooltip = #{@exprTypeTooltip}")
      @exprTypeTooltip?.updateText(fullName)
    )


  hideExpressionType: ->
    if @exprTypeTooltip?
      @exprTypeTooltip.remove()
      @exprTypeTooltip = null


module.exports = EditorControl