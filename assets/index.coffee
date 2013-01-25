guessDay = (year, month, day) ->
  if day isnt null
    day
  else
    date = new Date(year, month - 1, 1)
    (8 - date.getDay()) % 7 + 1

courseStartDate = (course) ->
  day = guessDay(course.start.year, course.start.month, course.start.day)
  new Date(course.start.year, course.start.month - 1, day)

courseEndDate = (course) ->
  date = courseStartDate(course)
  date.setDate(date.getDate() + course.duration)
  date

isoDate = (date) ->
  year = date.getFullYear()
  month = (date.getMonth() + 1).toString()
  month = "0#{month}" if month.length is 1
  day = date.getDate().toString()
  day = "0#{day}" if day.length is 1
  "#{year}-#{month}-#{day}"

$ ->
  userid = '218749b1617ef6f3b8ee9a75de9d6e01'
  $.getJSON "/coursera/#{userid}.json", (userdata) ->
    courses = _(userdata.courses).sortBy (course) ->
      courseStartDate(course).getTime()

    $container = $('.container')
      .on 'click', 'button.find-calendar', (e) ->
        $course = $(this).closest('.course')
        year = $course.data('year')
        month = $course.data('month')
        day = $course.data('day')
        $('#calendar').fullCalendar 'gotoDate', year, month, day

    courseTemplate = _.template '
      <div class="course" data-year="<%- start.year %>" data-month="<%- start.month %>" data-day="<%- start.day %>">
        <img class="logo" src="<%- photo %>" />
        <a class="title" href="<%- url %>"><%- name %></a>
        <% if (start.day === null) { %>
          <div class="start"><%- start.year %>-<%- start.month %></div>
        <% } else { %>
          <div class="start"><%- start.year %>-<%- start.month %>-<%- start.day %></div>
        <% } %>
        <div class="duration"><%- duration / 7 %> weeks</div>
        <button class="find-calendar">Find it</button>
      </div>
    '

    for course in courses
      $container.append courseTemplate(course)

    $('#calendar').fullCalendar
      events: courses
        .map (course) ->
          title: course.name
          start: isoDate(courseStartDate(course))
          end:   isoDate(courseEndDate(course))
