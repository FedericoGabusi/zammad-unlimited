class App.Ticket extends App.Model
  @configure 'Ticket', 'number', 'title', 'group_id', 'owner_id', 'customer_id', 'state_id', 'priority_id', 'article', 'tags', 'links', 'updated_at', 'preferences'
  @extend Spine.Model.Ajax
  @url: @apiPath + '/tickets'
  @configure_attributes = [
      { name: 'number',                   display: '#',            tag: 'input',    type: 'text', limit: 100, null: true, readonly: 1, width: '68px' },
      { name: 'title',                    display: __('Title'),        tag: 'input',    type: 'text', limit: 100, null: false },
      { name: 'customer_id',              display: __('Customer'),     tag: 'input',    type: 'text', limit: 100, null: false, autocapitalize: false, relation: 'User' },
      { name: 'organization_id',          display: __('Organization'), tag: 'select',   relation: 'Organization' },
      { name: 'group_id',                 display: __('Group'),        tag: 'select',   multiple: false, limit: 100, null: false, relation: 'Group', width: '10%', edit: true },
      { name: 'owner_id',                 display: __('Owner'),        tag: 'select',   multiple: false, limit: 100, null: true, relation: 'User', width: '12%', edit: true },
      { name: 'state_id',                 display: __('State'),        tag: 'select',   multiple: false, null: false, relation: 'TicketState', default: 'new', width: '12%', edit: true, customer: true },
      { name: 'pending_time',             display: __('Pending till'), tag: 'datetime', null: true, width: '130px' },
      { name: 'priority_id',              display: __('Priority'),     tag: 'select',   multiple: false, null: false, relation: 'TicketPriority', width: '54px', edit: true, customer: true },
      { name: 'article_count',            display: __('Article#'),     readonly: 1, width: '12%' },
      { name: 'time_unit',                display: __('Accounted Time'),          readonly: 1, width: '12%', tag: 'float' },
      { name: 'escalation_at',            display: __('Escalation at'),           tag: 'datetime', null: true, readonly: 1, width: '110px', class: 'escalation' },
      { name: 'first_response_escalation_at', display: __('Escalation at (First Response Time)'), tag: 'datetime', null: true, readonly: 1, width: '110px', class: 'escalation' },
      { name: 'update_escalation_at', display: __('Escalation at (Update Time)'), tag: 'datetime', null: true, readonly: 1, width: '110px', class: 'escalation' },
      { name: 'close_escalation_at', display: __('Escalation at (Close Time)'), tag: 'datetime', null: true, readonly: 1, width: '110px', class: 'escalation' },
      { name: 'last_contact_at',          display: __('Last contact'),            tag: 'datetime', null: true, readonly: 1, width: '110px' },
      { name: 'last_contact_agent_at',    display: __('Last contact (agent)'),    tag: 'datetime', null: true, readonly: 1, width: '110px' },
      { name: 'last_contact_customer_at', display: __('Last contact (customer)'), tag: 'datetime', null: true, readonly: 1, width: '110px' },
      { name: 'first_response_at',        display: __('First response'),          tag: 'datetime', null: true, readonly: 1, width: '110px' },
      { name: 'close_at',                 display: __('Closing time'),              tag: 'datetime', null: true, readonly: 1, width: '110px' },
      { name: 'created_by_id',            display: __('Created by'),   relation: 'User', readonly: 1 },
      { name: 'created_at',               display: __('Created at'),   tag: 'datetime', width: '110px', align: 'right', readonly: 1 },
      { name: 'updated_by_id',            display: __('Updated by'),   relation: 'User', readonly: 1 },
      { name: 'updated_at',               display: __('Updated at'),   tag: 'datetime', width: '110px', align: 'right', readonly: 1 },
    ]

  uiUrl: ->
    "#ticket/zoom/#{@id}"

  priorityIcon: ->
    priority = App.TicketPriority.findNative(@priority_id)
    return '' if !priority
    return '' if !priority.ui_icon
    return '' if !priority.ui_color
    App.Utils.icon(priority.ui_icon, "u-#{priority.ui_color}-color")

  priorityClass: ->
    priority = App.TicketPriority.findNative(@priority_id)
    return '' if !priority
    return '' if !priority.ui_color
    "item--#{priority.ui_color}"

  rowClass: ->
    @priorityClass()

  getState: ->
    type = App.TicketState.findNative(@state_id)
    stateType = App.TicketStateType.findNative(type.state_type_id)
    state = 'closed'
    if stateType.name is 'new' || stateType.name is 'open'
      state = 'open'

      # if ticket is escalated, overwrite state
      if @escalation_at && new Date( Date.parse(@escalation_at) ) < new Date
        state = 'escalating'
    else if stateType.name is 'pending reminder'
      state = 'pending'

      # if ticket pending_time is reached, overwrite state
      if @pending_time && new Date( Date.parse(@pending_time) ) < new Date
        state = 'open'
    else if stateType.name is 'pending action'
      state = 'pending'
    state

  icon: ->
    'task-state'

  iconClass: ->
    @getState()

  iconTitle: ->
    type = App.TicketState.findNative(@state_id)
    stateType = App.TicketStateType.findNative(type.state_type_id)
    if stateType.name is 'pending reminder' && @pending_time && new Date( Date.parse(@pending_time) ) < new Date
      return "#{App.i18n.translateInline(type.displayName())} - #{App.i18n.translateInline('reached')}"
    if @escalation_at && new Date( Date.parse(@escalation_at) ) < new Date
      return "#{App.i18n.translateInline(type.displayName())} - #{App.i18n.translateInline('escalated')}"
    App.i18n.translateInline(type.displayName())

  iconTextClass: ->
    "task-state-#{ @getState() }-color"

  iconActivity: (user) ->
    return if !user
    if @owner_id == user.id
      return 'important'
    ''
  searchResultAttributes: ->
    display:    "##{@number} - #{@title}"
    id:         @id
    class:      "task-state-#{ @getState() } ticket-popover"
    url:        @uiUrl()
    icon:       'task-state'
    iconClass:  @getState()

  activityMessage: (item) ->
    return if !item
    return if !item.created_by

    switch item.type
      when 'create'
        App.i18n.translateContent('%s created ticket |%s|', item.created_by.displayName(), item.title)
      when 'update'
        App.i18n.translateContent('%s updated ticket |%s|', item.created_by.displayName(), item.title)
      when 'reminder_reached'
        App.i18n.translateContent('Pending reminder reached for ticket |%s|', item.title)
      when 'escalation'
        App.i18n.translateContent('Ticket |%s| has escalated!', item.title)
      when 'escalation_warning'
        App.i18n.translateContent('Ticket |%s| will escalate soon!', item.title)
      when 'update.merged_into'
        App.i18n.translateContent('Ticket |%s| was merged into another ticket', item.title)
      when 'update.received_merge'
        App.i18n.translateContent('Another ticket was merged into ticket |%s|', item.title)
      else
        "Unknow action for (#{@objectDisplayName()}/#{item.type}), extend activityMessage() of model."

  # apply macro
  @macro: (params) ->
    for key, content of params.macro
      attributes = key.split('.')

      # apply ticket changes
      if attributes[0] is 'ticket'

        # apply tag changes
        if attributes[1] is 'tags'
          tags = content.value.split(/\s*,\s*/)
          for tag in tags
            if content.operator is 'remove'
              if params.callback && params.callback.tagRemove
                params.callback.tagRemove(tag)
              else
                @tagRemove(params.ticket.id, tag)
            else
              if params.callback && params.callback.tagAdd
                params.callback.tagAdd(tag)
              else
                @tagAdd(params.ticket.id, tag)

        # apply pending date changes
        else if attributes[1] is 'pending_time' && content.operator is 'relative'
          params.ticket[attributes[1]] = App.ViewHelpers.relative_time(content.value, content.range)

        # apply user changes
        else if attributes[1] is 'owner_id' || attributes[1] is 'customer_id'
          if content.pre_condition is 'current_user.id'
            params.ticket[attributes[1]] = App.Session.get('id')
          else
            params.ticket[attributes[1]] = content.value

        # apply direct value changes
        else
          params.ticket[attributes[1]] = content.value

      # apply article changes
      else if attributes[0] is 'article'

        # preload required attributes
        if !content.type_id
          type = App.TicketArticleType.findByAttribute('name', attributes[1])
          if type
            params.article.type_id = type.id
        if !content.sender_id
          sender = App.TicketArticleSender.findByAttribute('name', 'Agent')
          if sender
            content.sender_id = sender.id
        if !content.from
          content.from = App.Session.get('login')
        if !content.content_type
          params.article.content_type = 'text/html'

        # apply direct value changes
        for articleKey, aricleValue of content
          params.article[articleKey] = aricleValue

  editable: (permission = 'change') ->
    user = App.User.current()

    return false if !user?
    return true  if @editableByCustomer(user)

    return @userGroupAccess(permission)

  editableByCustomer: (user) ->
    return false if @currentView() != 'customer'
    return true  if @userIsCustomer()

    user.allOrganizationIds().includes(@organization_id)

  userGroupAccess: (permission) ->
    user = App.User.current()
    return @isAccessibleByGroup(user, permission)

  userIsCustomer: ->
    user = App.User.current()
    return true if user.id is @customer_id
    false

  userIsOwner: ->
    user = App.User.current()
    return @isAccessibleByOwner(user)

  currentView: ->
    return 'agent' if App.User.current()?.permission('ticket.agent') && @userGroupAccess('read')
    return 'customer' if App.User.current()?.permission('ticket.customer')
    return

  isAccessibleByOwner: (user) ->
    return false if !user
    return true if user.id is @owner_id
    false

  isAccessibleByGroup: (user, permission) ->
    return false if !user

    group_ids = user.allGroupIds(permission)
    return false if !@group_id

    for local_group_id in group_ids
      if local_group_id.toString() is @group_id.toString()
        return true

    return false

  isAccessibleBy: (user, permission) ->
    return false if !user
    return false if !user.permission('ticket.agent')
    return true if @isAccessibleByOwner(user)
    return @isAccessibleByGroup(user, permission)

  attributes: ->
    attrs = super

    if @shared_draft_id
      attrs.shared_draft_id = @shared_draft_id

    attrs

  displayName: ->
    return @title || '-'
