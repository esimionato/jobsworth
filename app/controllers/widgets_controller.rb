# encoding: UTF-8
class WidgetsController < ApplicationController
  OVERDUE    = 0
  TODAY      = 1
  TOMORROW   = 2
  THIS_WEEK  = 3
  NEXT_WEEK  = 4

  def show
    begin
      @widget = Widget.where("company_id = ? AND user_id = ?", current_user.company_id, current_user.id).find(params[:id])
    rescue
      render :nothing => true
      return
    end

    unless @widget.configured?
      render :partial => "widget_#{@widget.widget_type}_config"
      return
    end

    case @widget.widget_type
    when 0 then
      tasks_extracted_from_show
    when 1 then
      project_list_extracted_from_show
    when 2 then
      # Recent Activities : already removed
    when 3 then
      task_graph_extracted_from_show
    when 4 then
      burndown_extracted_from_show
    when 5 then
      burnup_extracted_from_show
    when 6 then
      comments_extracted_from_show
    when 7 then
      schedule_extracted_from_show
    when 8 then
      # Google Gadget
    when 9 then
      work_status_extracted_from_show
    when 10 then
      sheets_extracted_from_show
    end

    case @widget.widget_type
      when 0 then
        render :partial => 'tasks/task_list', :locals => { :tasks => @items }
      when 1 then
        render :partial => 'activities/project_overview'
      when 2 then
        # Recent Activities : already removed
      when 3..10 then
        render :partial => "widgets/widget_#{@widget.widget_type}"
    end

  end

  def add
    render :partial => "widgets/add"
  end

  def destroy
    begin
      @widget = Widget.where("company_id = ? AND user_id = ?", current_user.company_id, current_user.id).find(params[:id])
    rescue
      render :nothing => true
      return
    end
    render :update do |page|
      page << "var widget = $('#{@widget.dom_id}').widget;"
      page << "portal.remove(widget);"
    end
    @widget.destroy
  end

  def create
    @widget = Widget.new(params[:widget])
    @widget.user = current_user
    @widget.company = current_user.company
    @widget.configured = false
    @widget.column = 0
    @widget.position = 0
    @widget.collapsed = false

    unless @widget.save
      render :update do |page|
        page.visual_effect :shake, 'add-widget'
      end
      return
    else
      render :update do |page|
        page.remove 'add-widget'
        page << "var widget = new Xilinus.Widget('widget', '#{@widget.dom_id}');"
        page << "var title = '<div style=\"float:right;display:none;\" class=\"widget-menu\"><a href=\"#\" onclick=\"edit_widget(#{@widget.id},\\\'#{@widget.dom_id}\\\')\" return false;\"><img src=\"/images/configure.png\" border=\"0\"/></a><a href=\"#\" onclick=\"jQuery.getScript(\\\'/widgets/destroy/#{@widget.id}\\\'); return false;\"><img src=\"/images/delete.png\" border=\"0\"/></a></div>';"

        page << "title += '<div><a href=\"#\" id=\"indicator-#{@widget.dom_id}\" class=\"widget-open\" onclick=\"jQuery.get(\\\'/widgets/toggle_display/#{@widget.id}\\\',function(data) {portal.refreshHeights();} );\">&nbsp;</a>';"
        page << "title += '" + render_to_string(:partial => "widgets/widget_#{@widget.widget_type}_header.html.erb").gsub(/'/,'\\\\\'').split(/\n/).join + "</div>';"
        page.<< "widget.setTitle(title);"
        page << "widget.setContent('<span class=\"optional\">#{h(_('Please configure the widget'))}</span>');"
        page << "portal.add(widget, #{@widget.column});"
        page << "jQuery.get('/widgets/show/#{@widget.id}', function(data) {portal.refreshHeights();} );"

        page << "updateTooltips();"
        page << "portal.refreshHeights();"
        page << "Element.scrollTo('#{@widget.dom_id}');"
      end
    end
  end

  def edit
    begin
      @widget = Widget.where("company_id = ? AND user_id = ?", current_user.company_id, current_user.id).find(params[:id])
    rescue
      render :nothing => true
      return
    end
    render :partial => "widget_#{@widget.widget_type}_config.html.erb"
  end

  def update
    begin
      @widget = Widget.where("company_id = ? AND user_id = ?", current_user.company_id, current_user.id).find(params[:id])
    rescue
      render :nothing => true
      return
    end

    @widget.configured = true
    if @widget.update_attributes(params[:widget])
      render :json => {:widget_name => @widget.name, :widget_type => @widget.widget_type, :gadget_url => @widget.gadget_url, :configured => @widget.configured, :status => "success"}
    else
      render :nothing => true
    end
  end

  def save_order
    [0,1,2].each do |c|
      pos = 0
      if params["widget_col_#{c}"]
        params["widget_col_#{c}"].each do |id|
          w = current_user.widgets.find(id.split(/-/)[1]) rescue next
          w.column = c
          w.position = pos
          w.save
          pos += 1
        end
      end
    end
    render :nothing => true
  end

  def toggle_display
    begin
      @widget = current_user.widgets.find(params[:id])
    rescue
      render :nothing => true, :layout => false
      return
    end

    @widget.collapsed = !@widget.collapsed?
    @widget.save
    render :json => {:collapsed => @widget.collapsed?, :dom_id => @widget.dom_id}
  end

  private

  def filter_from_filter_by
    @widget.filter_from_filter_by
  end

  def tasks_extracted_from_show
     filter = filter_from_filter_by

      unless @widget.mine?
        @items = Task.accessed_by(current_user).where("tasks.completed_at IS NULL #{filter} AND (tasks.hide_until IS NULL OR tasks.hide_until < ?) AND (tasks.milestone_id NOT IN (?) OR tasks.milestone_id IS NULL)", tz.now.utc.to_s(:db), completed_milestone_ids).includes(:milestone,  :dependencies, :dependants, :todos, :tags)
      else
        @items = current_user.tasks.where("tasks.project_id IN (?) #{filter} AND tasks.completed_at IS NULL AND (tasks.hide_until IS NULL OR tasks.hide_until < ?) AND (tasks.milestone_id NOT IN (?) OR tasks.milestone_id IS NULL)", current_project_ids, tz.now.utc.to_s(:db), completed_milestone_ids).includes(:milestone, { :project => :customer }, :dependencies, :dependants, :todos, :tags)
      end

      @items = case @widget.order_by
               when 'priority' then
                   current_user.company.sort(@items)[0, @widget.number]
               when 'date' then
                   @items.sort_by {|t| t.created_at.to_i }[0, @widget.number]
               end
  end

  def project_list_extracted_from_show
    @projects = current_user.projects.order('t1_r2, projects.name, milestones.due_at IS NULL, milestones.due_at, milestones.name').where("projects.completed_at IS NULL").includes(:customer, :milestones)
    @completed_projects = current_user.completed_projects.size
  end

  def task_graph_extracted_from_show
    start, step, interval, range, tick = @widget.calculate_start_step_interval_range_tick(tz)

    filter = filter_from_filter_by

      @items = []
      @dates = []
      @range = []
      0.upto(range * step) do |d|

        unless @widget.mine?
          @items[d] = Task.accessed_by(current_user).where("tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter}", start + d*interval, start + d*interval).count
        else
          @items[d] = current_user.tasks.where("tasks.project_id IN (?) AND tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter}", current_project_ids, start + d*interval, start + d*interval).count
        end

        @dates[d] = tz.utc_to_local(start + d * interval - 1.hour).strftime(tick) if(d % step == 0)
        @range[0] ||= @items[d]
        @range[1] ||= @items[d]
        @range[0] = @items[d] if @range[0] > @items[d]
        @range[1] = @items[d] if @range[1] < @items[d]
      end
  end

  def  burndown_extracted_from_show
    start, step, interval, range, tick = @widget.calculate_start_step_interval_range_tick(tz)
      filter = filter_from_filter_by

      @items = []
      @dates = []
      @range = []
      velocity = 0
      0.upto(range * step) do |d|

        unless @widget.mine?
          @items[d] = Task.accessed_by(current_user).where("tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter}", start + d*interval, start + d*interval).sum('duration').to_f / current_user.workday_duration
          worked = Task.accessed_by(current_user).where("tasks.project_id IN (?) AND tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter} AND tasks.duration > 0 AND work_logs.started_at < ?", current_project_ids, start + d*interval, start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)
          @items[d] = (@items[d] - worked > 0) ? (@items[d] - worked) : 0

        else
          @items[d] = current_user.tasks.where("tasks.project_id IN (?) AND tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter}", current_project_ids, start + d*interval, start + d*interval).sum('duration').to_f / current_user.workday_duration
          worked = current_user.tasks.where("tasks.project_id IN (?) AND tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter} AND tasks.duration > 0 AND work_logs.started_at < ?", current_project_ids, start + d*interval, start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)
          @items[d] = (@items[d] - worked > 0) ? (@items[d] - worked) : 0
        end

        @dates[d] = tz.utc_to_local(start + d * interval - 1.hour).strftime(tick) if(d % step == 0)
        @range[0] ||= @items[d]
        @range[1] ||= @items[d]
        @range[0] = @items[d] if @range[0] > @items[d]
        @range[1] = @items[d] if @range[1] < @items[d]

      end

      velocity = (@items[0] - @items[-1]) / ((interval * range * step) / 1.day)
      velocity = velocity * (interval / 1.day)

      logger.info("Burndown Velocity: #{velocity}")

      @end_date = nil
      if velocity > 0.0
        days_left = @items[-1] / (velocity)
        @end_date = Time.now + days_left.days
        logger.info("Burndown Velocity left #{@items[-1]}")
        logger.info("Burndown Velocity days: #{days_left}")
        logger.info("Burndown Velocity End date: #{@end_date}")
      end

      start = @items[0]

      @velocity = []
      0.upto(range * step) do |d|
        @velocity[d] = start - velocity * d
      end
  end

  def burnup_extracted_from_show
    start, step, interval, range, tick = @widget.calculate_start_step_interval_range_tick(tz)
    filter = filter_from_filter_by

      @items  = []
      @totals = []
      @dates  = []
      @range  = []
      velocity = 0
      0.upto(range * step) do |d|

        unless @widget.mine?
          @totals[d]  = Task.accessed_by(current_user).where("tasks.created_at < ? AND tasks.duration > 0 #{filter}", start + d*interval).sum('duration').to_f / current_user.workday_duration
          @totals[d] += Task.accessed_by(current_user).where("tasks.created_at < ? AND tasks.duration = 0 AND work_logs.started_at < ? #{filter}", start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)

          @items[d] = Task.accessed_by(current_user).where("(tasks.completed_at IS NOT NULL AND tasks.completed_at < ?) #{filter} AND tasks.created_at < ?  AND tasks.duration > 0", start + d*interval, start + d*interval).sum('tasks.duration').to_f / current_user.workday_duration
          @items[d] += Task.accessed_by(current_user).where("tasks.created_at < ? AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) #{filter} AND tasks.duration = 0 AND work_logs.started_at < ?", start + d*interval, start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)
        else
          @totals[d]  = current_user.tasks.where("tasks.project_id IN (?) #{filter} AND tasks.created_at < ? AND tasks.duration > 0", current_project_ids, start + d*interval).sum('duration').to_f / current_user.workday_duration
          @totals[d] += current_user.tasks.where("tasks.project_id IN (?) #{filter} AND tasks.created_at < ? AND tasks.duration = 0 AND work_logs.started_at < ?", current_project_ids, start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)

          @items[d] = current_user.tasks.where("tasks.project_id IN (?) #{filter} AND (tasks.completed_at IS NOT NULL AND tasks.completed_at < ?) AND tasks.created_at < ?  AND tasks.duration > 0", current_project_ids, start + d*interval, start + d*interval).sum('tasks.duration').to_f / current_user.workday_duration
          @items[d] += current_user.tasks.where("tasks.project_id IN (?) #{filter} AND tasks.created_at < ?  AND tasks.duration = 0 AND (tasks.completed_at IS NULL OR tasks.completed_at > ?) AND work_logs.started_at < ?", current_project_ids, start + d*interval, start + d*interval, start + d*interval).includes(:work_logs).sum('work_logs.duration').to_f / (current_user.workday_duration * 60)
        end

        @dates[d] = tz.utc_to_local(start + d * interval - 1.hour).strftime(tick) if(d % step == 0)
        @range[0] ||= @items[d]
        @range[1] ||= @items[d]
        @range[0] = @items[d] if @range[0] > @items[d]
        @range[1] = @items[d] if @range[1] < @items[d]

        @range[0] = @totals[d] if @range[0] > @totals[d]
        @range[1] = @totals[d] if @range[1] < @totals[d]

      end

      velocity = (@items[0] - @items[-1]) / ((interval * range * step) / 1.day)
      velocity = velocity * (interval/1.day)

      logger.info("Burnup Velocity: #{velocity}")
      @end_date = nil
      if velocity < 0.0
        days_left = (@totals[-1] - @items[-1]) / (-velocity)
        @end_date = Time.now + days_left.days
        logger.info("Burnup Velocity left: #{@totals[-1] - @items[-1]}")
        logger.info("Burnup Velocity days: #{days_left}")
        logger.info("Burnup Velocity End date: #{@end_date}")
      end

      start = @items[0]

      @velocity = []
      0.upto(range * step) do |d|
        @velocity[d] = start - velocity * d
      end
  end

  def comments_extracted_from_show
    if @widget.mine?
      @items = WorkLog.comments.on_tasks_owned_by(current_user).accessed_by(current_user).order("started_at desc").limit(@widget.number)
    else
      @items = WorkLog.comments.accessed_by(current_user).order("started_at desc").limit(@widget.number)
    end
  end

  def schedule_extracted_from_show
      filter = filter_from_filter_by

      if @widget.mine?
        tasks = current_user.tasks.includes(:users, :tags, :sheets, :todos, :dependencies, :dependants, { :project => :customer}, :milestone).where("tasks.completed_at IS NULL AND projects.completed_at IS NULL #{filter} AND (tasks.due_at IS NOT NULL OR tasks.milestone_id IS NOT NULL)")
      else
        tasks = Task.accessed_by(current_user).includes(:tags, :sheets, :todos, :dependencies, :dependants, :milestone).where("tasks.completed_at IS NULL AND projects.completed_at IS NULL #{filter} AND (tasks.due_at IS NOT NULL OR tasks.milestone_id IS NOT NULL)")
      end
      # first use default sorting
      tasks = tasks.sort_by { |t| t.due_date.to_i }
      @tasks = []

      tasks.each do |t|
        next if t.due_date.nil?

        if t.overdue?
          (@tasks[OVERDUE] ||= []) << t
        elsif t.due_date < ( tz.local_to_utc(tz.now.utc.tomorrow.midnight) )
          (@tasks[TODAY] ||= []) << t
        elsif t.due_date < ( tz.local_to_utc(tz.now.utc.since(2.days).midnight) )
          (@tasks[TOMORROW] ||= []) << t
        elsif t.due_date < ( tz.local_to_utc(tz.now.utc.next_week.beginning_of_week) )
          (@tasks[THIS_WEEK] ||= []) << t
        elsif t.due_date < ( tz.local_to_utc(tz.now.utc.since(2.weeks).beginning_of_week) )
          (@tasks[NEXT_WEEK] ||= []) << t
        end
      end
  end

  def work_status_extracted_from_show
    @last_completed = @widget.last_completed
    @counts = @widget.counts
  end

  def sheets_extracted_from_show
    filter = filter_from_filter_by
    @sheets = Sheet.order('users.name').includes(:user, :task, :project ).where("tasks.project_id IN (?) #{filter}", current_project_ids)
  end
end
