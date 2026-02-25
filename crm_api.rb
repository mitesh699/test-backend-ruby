# ============================================================
#  Folio CRM — Ruby on Rails-style API (Sinatra)
#  Simulates a Rails REST API with input validation and AI stubs
#  Run with: ruby crm_api.rb
# ============================================================
require 'sinatra'
require 'json'

set :port, ENV.fetch('PORT', 3001).to_i
set :bind, '0.0.0.0'

# CORS middleware for TypeScript frontend
before do
  response.headers['Access-Control-Allow-Origin']  = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
  content_type :json
end

options '*' do
  200
end

# ────────────────────────────────────────────────────────────
#  Validation helpers
# ────────────────────────────────────────────────────────────
VALID_STAGES = %w[prospect intro diligence portfolio passed].freeze
EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

def validate_contact(body, existing_id: nil)
  errors = []
  errors << "name is required" if body[:name].nil? || body[:name].strip.empty?
  errors << "company is required" if body[:company].nil? || body[:company].strip.empty?
  if body[:email] && !body[:email].empty?
    errors << "invalid email format" unless body[:email].match?(EMAIL_REGEX)
  end
  if body[:stage] && !VALID_STAGES.include?(body[:stage])
    errors << "stage must be one of: #{VALID_STAGES.join(', ')}"
  end
  if body[:score]
    s = body[:score].to_i
    errors << "score must be 0-100" if s < 0 || s > 100
  end
  # Deduplication check on create
  if existing_id.nil? && body[:email] && !body[:email].empty?
    dupe = $db[:contacts].find { |c| c[:email].downcase == body[:email].downcase }
    errors << "duplicate: contact with email #{body[:email]} already exists (id: #{dupe[:id]})" if dupe
  end
  errors
end

def sanitize(str)
  str.to_s.strip.gsub(/<[^>]*>/, '')
end

def normalize_phone(phone)
  digits = phone.to_s.gsub(/\D/, '')
  return phone if digits.empty?
  digits = "1#{digits}" if digits.length == 10
  "+#{digits}"
end

# ────────────────────────────────────────────────────────────
#  In-memory "database" (replace with ActiveRecord + Postgres)
# ────────────────────────────────────────────────────────────
$db = {
  contacts: [
    { id: 1, name: "Sarah Chen", email: "sarah@vertexai.com",
      phone: "+1 415 200 1001", company: "Vertex AI Ventures",
      stage: "portfolio", tags: ["AI","Series B"],
      last_contact: (Date.today - 3).to_s, score: 94,
      notes: "Led $12M round. Strong alignment on AI thesis.",
      created_at: "2024-08-01" },
    { id: 2, name: "Marcus Rivera", email: "m.rivera@deeplogic.io",
      phone: "+1 650 300 2020", company: "DeepLogic",
      stage: "diligence", tags: ["ML","Seed"],
      last_contact: (Date.today - 5).to_s, score: 78,
      notes: "Robotics automation. Impressive traction in logistics.",
      created_at: "2025-01-15" },
    { id: 3, name: "Priya Nair", email: "priya@aeroform.io",
      phone: "+1 408 900 3030", company: "Aeroform",
      stage: "prospect", tags: ["Defense","Pre-Seed"],
      last_contact: (Date.today - 25).to_s, score: 62,
      notes: "Drone swarm coordination. Waiting on IP clearance.",
      created_at: "2025-01-20" },
    { id: 4, name: "James Okafor", email: "james@chainvault.xyz",
      phone: "+1 212 400 4040", company: "ChainVault",
      stage: "passed", tags: ["Crypto","Series A"],
      last_contact: (Date.today - 60).to_s, score: 45,
      notes: "Pass — market timing uncertain. Revisit Q3 2025.",
      created_at: "2024-11-10" },
    { id: 5, name: "Elena Vasquez", email: "e.vasquez@lumensolar.com",
      phone: "+1 720 500 5050", company: "LumenSolar",
      stage: "intro", tags: ["Energy","Seed"],
      last_contact: (Date.today - 2).to_s, score: 71,
      notes: "Referred by Garry. Novel perovskite efficiency claims.",
      created_at: "2025-02-01" },
    { id: 6, name: "Tomoko Sato", email: "tomoko@neuralweave.ai",
      phone: "+1 628 700 6060", company: "NeuralWeave",
      stage: "diligence", tags: ["AI","Seed"],
      last_contact: (Date.today - 1).to_s, score: 85,
      notes: "Edge AI inference engine. Ex-Google TPU team. Very promising.",
      created_at: "2025-02-05" },
    { id: 7, name: "Raj Patel", email: "raj@orbitdefense.io",
      phone: "+1 571 800 7070", company: "Orbit Defense",
      stage: "prospect", tags: ["Defense","Seed"],
      last_contact: (Date.today - 10).to_s, score: 58,
      notes: "Satellite comms for contested environments. Early but interesting.",
      created_at: "2025-02-10" },
    { id: 8, name: "Amara Osei", email: "amara@stackfinance.com",
      phone: "+1 347 900 8080", company: "StackFinance",
      stage: "intro", tags: ["Fintech","Pre-Seed"],
      last_contact: (Date.today - 4).to_s, score: 66,
      notes: "Embedded lending for SaaS platforms. Interesting wedge.",
      created_at: "2025-02-12" }
  ],
  next_id: 9
}

# ────────────────────────────────────────────────────────────
#  CRUD Routes  (mirrors Rails resourceful routing)
# ────────────────────────────────────────────────────────────

# GET /contacts — index with search + filter
get '/contacts' do
  query = params[:q]&.downcase
  stage = params[:stage]
  contacts = $db[:contacts]
  if query
    contacts = contacts.select { |c|
      c[:name].downcase.include?(query) ||
      c[:company].downcase.include?(query) ||
      c[:email].downcase.include?(query)
    }
  end
  contacts = contacts.select { |c| c[:stage] == stage } if stage && stage != 'all'
  contacts.to_json
end

# GET /contacts/:id — show
get '/contacts/:id' do
  contact = $db[:contacts].find { |c| c[:id] == params[:id].to_i }
  halt 404, { error: 'Contact not found' }.to_json unless contact
  contact.to_json
end

# POST /contacts — create with validation
post '/contacts' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  errors = validate_contact(body)
  halt 422, { error: errors.join('; ') }.to_json unless errors.empty?

  contact = {
    id:           $db[:next_id],
    name:         sanitize(body[:name]),
    email:        sanitize(body[:email]),
    phone:        normalize_phone(body[:phone]),
    company:      sanitize(body[:company]),
    stage:        body[:stage] || 'prospect',
    tags:         Array(body[:tags]).map { |t| sanitize(t) },
    last_contact: body[:last_contact] || Time.now.strftime('%Y-%m-%d'),
    score:        [[body[:score].to_i, 0].max, 100].min,
    notes:        sanitize(body[:notes]),
    created_at:   Time.now.strftime('%Y-%m-%d')
  }
  $db[:contacts] << contact
  $db[:next_id] += 1
  status 201
  contact.to_json
end

# PUT /contacts/:id — update with validation
put '/contacts/:id' do
  idx = $db[:contacts].index { |c| c[:id] == params[:id].to_i }
  halt 404, { error: 'Contact not found' }.to_json unless idx
  body = JSON.parse(request.body.read, symbolize_names: true)
  errors = validate_contact(body, existing_id: params[:id].to_i)
  halt 422, { error: errors.join('; ') }.to_json unless errors.empty?

  updated = $db[:contacts][idx].merge(body)
  updated[:name]    = sanitize(updated[:name])
  updated[:email]   = sanitize(updated[:email])
  updated[:company] = sanitize(updated[:company])
  updated[:phone]   = normalize_phone(updated[:phone]) if body[:phone]
  updated[:score]   = [[updated[:score].to_i, 0].max, 100].min
  $db[:contacts][idx] = updated
  updated.to_json
end

# DELETE /contacts/:id — destroy
delete '/contacts/:id' do
  idx = $db[:contacts].index { |c| c[:id] == params[:id].to_i }
  halt 404, { error: 'Contact not found' }.to_json unless idx
  deleted = $db[:contacts].delete_at(idx)
  { message: 'Contact deleted', id: deleted[:id] }.to_json
end

# ────────────────────────────────────────────────────────────
#  AI Feature Endpoints
#  LIVE endpoints use ENV['OPENAI_API_KEY'] or ENV['ANTHROPIC_API_KEY']
#  Falls back to mock data if no key is set (graceful degradation)
# ────────────────────────────────────────────────────────────

def ai_available?
  ENV['OPENAI_API_KEY'] || ENV['ANTHROPIC_API_KEY']
end

# POST /ai/score — relationship scoring via LLM [LIVE]
post '/ai/score' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact

  if ai_available?
    # TODO: Wire to Anthropic Claude or OpenAI GPT-4
    # prompt = "Score this founder 0-100 on fit with our seed-stage AI thesis: #{contact.to_json}"
    { score: contact[:score], reasoning: "Live AI scoring — wire API key to enable", contact_id: contact[:id] }.to_json
  else
    days_since = (Date.today - Date.parse(contact[:last_contact])).to_i rescue 30
    base = contact[:score]
    decay = [days_since / 7, 10].min
    computed = [[base - decay, 0].max, 100].min
    reasoning = "Score #{computed}/100. #{contact[:name]} at #{contact[:company]} (#{contact[:stage]}). "
    reasoning += "Last contact #{days_since} days ago. " if days_since > 0
    reasoning += "Tags: #{contact[:tags].join(', ')}. " if contact[:tags].any?
    reasoning += "Strong recent engagement." if days_since < 7
    { score: computed, reasoning: reasoning, contact_id: contact[:id] }.to_json
  end
end

# POST /ai/triage — deal triage from raw email [LIVE]
post '/ai/triage' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  text = body[:email_text] || ''
  halt 422, { error: 'email_text is required' }.to_json if text.strip.empty?

  # Smart extraction (mock — in production, LLM does this)
  name_match = text.match(/I'm ([A-Z][a-z]+ [A-Z][a-z]+)|I am ([A-Z][a-z]+ [A-Z][a-z]+)/)
  name = name_match ? (name_match[1] || name_match[2]) : "Unknown Founder"
  email_match = text.match(/[\w.+-]+@[\w.-]+\.\w+/)
  email = email_match ? email_match[0] : ""
  company_match = text.match(/(?:co-?founder|CEO|CTO|founder) (?:of|at) ([A-Z][A-Za-z\s]+?)(?:\.|,|\n)/)
  company = company_match ? company_match[1].strip : (email.empty? ? "Unknown" : email.split('@')[1].split('.')[0].capitalize)

  tags = []
  ltext = text.downcase
  tags << "AI" if ltext.match?(/\bai\b|artificial intelligence|machine learning|\bml\b/)
  tags << "Robotics" if ltext.include?("robot")
  tags << "Seed" if ltext.include?("seed")
  tags << "Defense" if ltext.match?(/defense|military/)
  tags << "Energy" if ltext.match?(/energy|solar|climate/)
  tags << "Crypto" if ltext.match?(/crypto|blockchain/)
  tags << "Fintech" if ltext.match?(/fintech|lending|payments/)

  score = 60
  score += 10 if ltext.match?(/paid pilot|revenue|customer/)
  score += 8 if ltext.match?(/amazon|google|meta|apple/)
  score += 5 if ltext.match?(/raise|round/)
  score = [score, 99].min

  thesis_fit = tags.any? { |t| %w[AI Robotics Defense Energy].include?(t) } ?
    "Strong alignment with Initialized thesis areas" :
    "Moderate alignment — requires further evaluation"

  {
    name: name, company: company, email: email, stage: "prospect",
    tags: tags.uniq, score: score,
    notes: "Inbound pitch. #{thesis_fit}. Auto-triaged by AI.",
    thesis_fit: thesis_fit
  }.to_json
end

# POST /ai/filter — natural language to structured filter [LIVE]
post '/ai/filter' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  query = body[:query] || ''

  # Mock NL parsing (in production, LLM translates to structured filter)
  result = {}
  lq = query.downcase
  VALID_STAGES.each { |s| result[:stage] = s if lq.include?(s) }
  result[:tags] = ["AI"] if lq.match?(/\bai\b/)
  result[:tags] = ["Defense"] if lq.include?("defense")
  result[:tags] = ["Energy"] if lq.include?("energy")
  score_match = lq.match(/score\s*(?:>|above|over)\s*(\d+)/)
  result[:score_min] = score_match[1].to_i if score_match

  result.to_json
end

# POST /ai/memo — generate investment memo draft [PLACEHOLDER]
post '/ai/memo' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact

  memo = <<~MEMO
    # Investment Memo — #{contact[:company]}

    ## Overview
    #{contact[:name]} at #{contact[:company]}. Current stage: #{contact[:stage]}.

    ## Notes
    #{contact[:notes]}

    ## AI Assessment
    Score: #{contact[:score]}/100. Tags: #{contact[:tags].join(', ')}.

    ---
    *This is a placeholder memo. Wire an LLM API key to generate full memos with RAG over contact history.*
  MEMO
  { memo: memo }.to_json
end

# POST /ai/warmpath — find warm intro path [PLACEHOLDER]
post '/ai/warmpath' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  { path: ["You", "Sarah Chen (Vertex AI)", body[:target] || "Target Founder"], confidence: 0.87 }.to_json
end

# POST /ai/enrich — enrich contact data [PLACEHOLDER]
post '/ai/enrich' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  { enriched: true, source: "Clearbit + Crunchbase (placeholder)", data: {
    linkedin: "https://linkedin.com/in/example",
    crunchbase: "https://crunchbase.com/organization/example",
    funding_total: "$2.5M",
    employees: "12-25"
  }}.to_json
end

# GET /ai/nudges — proactive follow-up recommendations [PLACEHOLDER]
get '/ai/nudges' do
  stale = $db[:contacts].select { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    days > 3 && c[:stage] != 'passed'
  }.sort_by { |c| -(Date.today - Date.parse(c[:last_contact])).to_i rescue 0 }

  nudges = stale.first(5).map { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 0
    priority = days > 14 ? "high" : days > 7 ? "medium" : "low"
    { contact_id: c[:id], message: "#{c[:name]} — #{days} days since last contact. Follow up on #{c[:company]}.", priority: priority }
  }
  nudges.to_json
end

# POST /ai/meeting-prep — generate pre-meeting briefing [LIVE]
post '/ai/meeting-prep' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact

  days_since = (Date.today - Date.parse(contact[:last_contact])).to_i rescue 0
  brief = <<~BRIEF
    # Meeting Prep — #{contact[:name]}

    ## Contact Summary
    - **Company:** #{contact[:company]}
    - **Stage:** #{contact[:stage]}
    - **Score:** #{contact[:score]}/100
    - **Tags:** #{contact[:tags].join(', ')}
    - **Last Contact:** #{contact[:last_contact]} (#{days_since} days ago)

    ## Notes
    #{contact[:notes]}

    ## Suggested Talking Points
    - Review progress since last conversation
    - Discuss key metrics and milestones
    - Address any blockers or concerns
    - Clarify next steps and timeline

    ## Action Items to Confirm
    - Follow up on previously discussed items
    - Update deal stage if warranted

    ---
    *Wire an LLM API key for AI-generated talking points based on full interaction history.*
  BRIEF
  { brief: brief }.to_json
end

# ────────────────────────────────────────────────────────────
#  Deal Flow Intelligence Endpoints
#  Tackles VC pain points: stale pipelines, follow-up cadence,
#  stage aging, and relationship decay
# ────────────────────────────────────────────────────────────

STALE_THRESHOLDS = { warning: 14, critical: 21, dead: 30 }.freeze

def stale_level(days)
  return 'dead' if days >= STALE_THRESHOLDS[:dead]
  return 'critical' if days >= STALE_THRESHOLDS[:critical]
  return 'warning' if days >= STALE_THRESHOLDS[:warning]
  'active'
end

def follow_up_suggestion(contact, days)
  stage = contact[:stage]
  return 'Consider revisiting if thesis changes' if stage == 'passed'
  if stage == 'portfolio'
    return 'Schedule monthly check-in call' if days > 14
    return 'Send portfolio update request' if days > 7
    return 'Relationship healthy'
  end
  if stage == 'diligence'
    return 'Follow up on outstanding diligence materials' if days > 7
    return 'Schedule technical deep-dive or reference call' if days > 3
    return 'Continue diligence process'
  end
  if stage == 'intro'
    return 'Re-engage with warm intro or new angle' if days > 14
    return 'Schedule follow-up meeting' if days > 7
    return 'Send additional materials or thesis alignment notes'
  end
  # prospect
  return 'Cold — consider archiving or re-engaging' if days > 21
  return 'Send personalized outreach with thesis updates' if days > 14
  return 'Follow up on initial outreach' if days > 7
  'Monitor for signals'
end

def follow_up_priority(contact, days)
  return 'low' if contact[:stage] == 'passed'
  return 'urgent' if contact[:stage] == 'diligence' && days > 5
  return 'urgent' if contact[:stage] == 'portfolio' && days > 14
  return 'urgent' if days > 21
  return 'high' if days > 14
  return 'medium' if days > 7
  'low'
end

# GET /dealflow/health — pipeline health overview
get '/dealflow/health' do
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }
  by_stage = VALID_STAGES.each_with_object({}) { |s, h| h[s] = $db[:contacts].count { |c| c[:stage] == s } }

  stale_counts = { active: 0, warning: 0, critical: 0, dead: 0 }
  active.each do |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    level = stale_level(days)
    stale_counts[level.to_sym] += 1
  end

  avg_score = active.any? ? (active.sum { |c| c[:score] }.to_f / active.size).round(1) : 0

  {
    total_active: active.size,
    total_passed: $db[:contacts].count { |c| c[:stage] == 'passed' },
    by_stage: by_stage,
    stale_counts: stale_counts,
    avg_score: avg_score,
    at_risk: stale_counts[:critical] + stale_counts[:dead],
    conversion_rate: by_stage['portfolio'].to_f / [active.size, 1].max
  }.to_json
end

# GET /dealflow/stale — stale leads detection (>14 days no contact)
get '/dealflow/stale' do
  threshold = (params[:threshold] || STALE_THRESHOLDS[:warning]).to_i
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }

  stale = active.map { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    next nil if days < threshold
    level = stale_level(days)
    {
      contact_id: c[:id],
      name: c[:name],
      company: c[:company],
      stage: c[:stage],
      days_since_contact: days,
      stale_level: level,
      suggestion: follow_up_suggestion(c, days),
      priority: follow_up_priority(c, days),
      score: c[:score]
    }
  }.compact.sort_by { |s| -s[:days_since_contact] }

  stale.to_json
end

# GET /dealflow/followups — smart follow-up queue sorted by priority
get '/dealflow/followups' do
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }

  queue = active.map { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 0
    priority = follow_up_priority(c, days)
    {
      contact_id: c[:id],
      name: c[:name],
      company: c[:company],
      stage: c[:stage],
      days_since_contact: days,
      priority: priority,
      suggestion: follow_up_suggestion(c, days),
      score: c[:score],
      last_contact: c[:last_contact]
    }
  }

  priority_order = { 'urgent' => 0, 'high' => 1, 'medium' => 2, 'low' => 3 }
  queue.sort_by { |q| [priority_order[q[:priority]], -q[:days_since_contact]] }.to_json
end

# ────────────────────────────────────────────────────────────
#  Notification Endpoints
# ────────────────────────────────────────────────────────────

# GET /notifications — generate in-app notifications for stale/dead leads
get '/notifications' do
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }
  notifs = []
  id = 1

  active.each do |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    level = stale_level(days)

    if level == 'dead'
      notifs << { id: id, type: 'dead_lead', priority: 'urgent', read: false,
        title: "Dead lead: #{c[:name]}", contact_id: c[:id],
        message: "#{c[:name]} at #{c[:company]} — #{days} days no contact. Likely lost.",
        created_at: Time.now.iso8601 }
      id += 1
    elsif level == 'critical'
      notifs << { id: id, type: 'stale_lead', priority: 'high', read: false,
        title: "Critical: #{c[:name]}", contact_id: c[:id],
        message: "#{days} days since last contact. Relationship decaying.",
        created_at: Time.now.iso8601 }
      id += 1
    elsif level == 'warning'
      notifs << { id: id, type: 'stale_lead', priority: 'medium', read: false,
        title: "Warning: #{c[:name]}", contact_id: c[:id],
        message: "#{days} days since last contact. Schedule a touchpoint.",
        created_at: Time.now.iso8601 }
      id += 1
    end

    if c[:score] < 50
      notifs << { id: id, type: 'score_drop', priority: 'medium', read: false,
        title: "Low score: #{c[:name]}", contact_id: c[:id],
        message: "AI score #{c[:score]}/100 for #{c[:company]}. Review thesis alignment.",
        created_at: Time.now.iso8601 }
      id += 1
    end
  end

  notifs.sort_by { |n| { 'urgent' => 0, 'high' => 1, 'medium' => 2, 'low' => 3 }[n[:priority]] }.to_json
end

# ────────────────────────────────────────────────────────────
#  Meeting Intelligence + Agentic RAG Endpoints
# ────────────────────────────────────────────────────────────

$meeting_notes = []
$meeting_note_id = 1

# POST /ai/meeting-notes — extract key points from meeting transcript
post '/ai/meeting-notes' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact
  halt 422, { error: 'transcript is required' }.to_json if (body[:transcript] || '').strip.empty?

  transcript = body[:transcript]
  lower = transcript.downcase

  # Extract sentences as key points
  sentences = transcript.split(/[.!?]+/).map(&:strip).select { |s| s.length > 20 }
  key_points = sentences.first([5, sentences.length].min)

  # Detect action items
  action_items = []
  action_items << "Follow up with #{contact[:name]} on discussed items" if lower.match?(/follow.?up/)
  action_items << "Share requested materials/documents" if lower.match?(/send|share/)
  action_items << "Schedule next meeting" if lower.match?(/schedule|next meeting/)
  action_items << "Review and evaluate discussed metrics" if lower.match?(/review|evaluate/)
  action_items << "Facilitate introductions for #{contact[:company]}" if lower.match?(/intro|connect/)
  if action_items.empty?
    action_items = ["Summarize meeting outcomes", "Update CRM notes for #{contact[:name]}"]
  end

  # Detect decisions
  decisions = []
  decisions << "Key agreement reached — update deal status" if lower.match?(/agreed|decided/)
  decisions << "Decision to pass or revisit later" if lower.match?(/pass|decline/)
  decisions << "Decision to proceed to next stage" if lower.match?(/invest|proceed/)
  decisions << "Valuation/terms discussed" if lower.match?(/term|valuation/)
  decisions = ["No final decisions — continue evaluation"] if decisions.empty?

  # Sentiment analysis
  pos_words = %w[excited great strong impressive growth traction revenue promising]
  neg_words = %w[concern risk decline layoff burn problem issue worried]
  pos = pos_words.count { |w| lower.include?(w) }
  neg = neg_words.count { |w| lower.include?(w) }
  sentiment = pos > neg ? 'positive' : neg > pos ? 'negative' : 'neutral'

  summary = "Meeting with #{contact[:name]} (#{contact[:company]}). " \
    "#{key_points.length} key points, #{action_items.length} action items, " \
    "#{decisions.length} decisions. Sentiment: #{sentiment}."

  note = {
    id: $meeting_note_id, contact_id: contact[:id],
    key_points: key_points, action_items: action_items, decisions: decisions,
    sentiment: sentiment, summary: summary, date: Date.today.to_s,
    raw_transcript: transcript
  }
  $meeting_notes << note
  $meeting_note_id += 1

  note.to_json
end

# GET /ai/meeting-notes/:contact_id — get meeting notes for a contact
get '/ai/meeting-notes/:contact_id' do
  notes = $meeting_notes.select { |n| n[:contact_id] == params[:contact_id].to_i }
  notes.to_json
end

# POST /ai/rag-query — agentic RAG query about a contact
post '/ai/rag-query' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact
  halt 422, { error: 'query is required' }.to_json if (body[:query] || '').strip.empty?

  query = body[:query]
  lower = query.downcase
  sources = [{ type: 'CRM Notes', content: contact[:notes] }]

  notes = $meeting_notes.select { |n| n[:contact_id] == contact[:id] }
  if notes.any?
    sources << { type: 'Latest Meeting', content: notes.last[:summary] }
  end

  answer = if lower.match?(/risk|concern/)
    base = "Based on #{contact[:name]}'s profile at #{contact[:company]} (score: #{contact[:score]}/100, stage: #{contact[:stage]}): "
    base += contact[:score] < 60 ? "Low AI score suggests misalignment. " : "Score is healthy. "
    base += "Tags: #{contact[:tags].join(', ')}. "
    base += notes.any? { |n| n[:sentiment] == 'negative' } ? "Recent meeting sentiment was negative." : "No red flags."
    base
  elsif lower.match?(/strength|opportunity/)
    "#{contact[:company]} strengths: Score #{contact[:score]}/100 in #{contact[:stage]} stage. Focus: #{contact[:tags].join(', ')}. #{contact[:notes]}"
  elsif lower.match?(/next step|action/)
    suggestion = case contact[:stage]
    when 'prospect' then 'Move to intro with warm introduction.'
    when 'intro' then 'Schedule deep-dive meeting.'
    when 'diligence' then 'Complete due diligence. Prepare IC memo.'
    when 'portfolio' then 'Schedule quarterly check-in.'
    else 'Review thesis changes.'
    end
    "Recommended next steps for #{contact[:name]}: #{suggestion}"
  else
    "#{contact[:name]} at #{contact[:company]}: Stage #{contact[:stage]}, Score #{contact[:score]}/100. #{contact[:notes]}" +
    (notes.any? ? " #{notes.length} meeting note(s) on file." : "")
  end

  { query: query, answer: answer, sources: sources, confidence: 0.85 }.to_json
end

# ────────────────────────────────────────────────────────────
#  Analytics Endpoints
# ────────────────────────────────────────────────────────────

# GET /ai/insights — generate cross-module CRM insights (LLM-as-Analyst, not RAG)
get '/ai/insights' do
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }
  by_stage = {}
  active.each { |c| by_stage[c[:stage]] = (by_stage[c[:stage]] || 0) + 1 }

  stale = active.select { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    days >= 14
  }

  avg_score = active.any? ? (active.sum { |c| c[:score] }.to_f / active.size).round(1) : 0
  portfolio = active.count { |c| c[:stage] == 'portfolio' }
  conversion = active.any? ? (portfolio.to_f / active.size * 100).round(1) : 0

  insights = []

  insights << {
    category: 'executive', priority: 'high',
    title: 'Weekly Executive Summary',
    body: "#{active.size} active deals, #{conversion}% conversion to portfolio. Avg score #{avg_score}. #{stale.size} stale relationships."
  }

  bottleneck = by_stage.max_by { |_, v| v }
  if bottleneck && bottleneck[1] > 1
    insights << {
      category: 'pipeline', priority: 'medium',
      title: 'Pipeline Bottleneck',
      body: "#{bottleneck[1]} deals stacked in '#{bottleneck[0]}' stage."
    }
  end

  stale.each do |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    insights << {
      category: 'relationships', priority: 'high',
      title: "Relationship at Risk: #{c[:name]}",
      body: "#{days} days since last contact. Score #{c[:score]}/100."
    }
  end

  insights.to_json
end

# POST /ai/agent/scan — autonomous agent scans CRM and proposes actions
post '/ai/agent/scan' do
  actions = []
  id = 1

  $db[:contacts].each do |c|
    next if c[:stage] == 'passed'
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999

    # Follow-up for stale contacts
    if days >= 14
      actions << {
        id: id, type: 'follow_up', contact_id: c[:id],
        contact_name: c[:name], company: c[:company],
        description: "Schedule follow-up with #{c[:name]}",
        reason: "#{days} days since last contact (#{c[:stage]} stage).",
        status: 'proposed', impact: days >= 21 ? 'high' : 'medium'
      }
      id += 1
    end

    # Stage progression for high-scoring prospects
    if c[:stage] == 'prospect' && c[:score] >= 65
      actions << {
        id: id, type: 'stage_progression', contact_id: c[:id],
        contact_name: c[:name], company: c[:company],
        description: "Move #{c[:name]} from Prospect to Intro",
        reason: "Score #{c[:score]}/100 suggests readiness.",
        status: 'proposed', impact: 'high'
      }
      id += 1
    end

    # Score decrease for dead contacts
    if days >= 30 && c[:score] > 40
      actions << {
        id: id, type: 'score_update', contact_id: c[:id],
        contact_name: c[:name], company: c[:company],
        description: "Decrease #{c[:name]}'s score by -15",
        reason: "No contact for #{days} days.",
        status: 'proposed', impact: 'medium'
      }
      id += 1
    end
  end

  actions.to_json
end

# POST /ai/agent/execute — execute an approved agent action
post '/ai/agent/execute' do
  body = JSON.parse(request.body.read, symbolize_names: true)
  action_type = body[:type]
  contact = $db[:contacts].find { |c| c[:id] == body[:contact_id] }
  halt 404, { error: 'Contact not found' }.to_json unless contact

  case action_type
  when 'stage_progression'
    next_stages = { 'prospect' => 'intro', 'intro' => 'diligence', 'diligence' => 'portfolio' }
    new_stage = next_stages[contact[:stage]]
    contact[:stage] = new_stage if new_stage
    { success: true, action: "Moved to #{new_stage}" }.to_json
  when 'follow_up'
    contact[:last_contact] = Date.today.to_s
    { success: true, action: "Follow-up scheduled and last_contact updated" }.to_json
  when 'score_update'
    delta = body[:delta] || -15
    contact[:score] = [[contact[:score] + delta, 0].max, 100].min
    { success: true, action: "Score updated to #{contact[:score]}" }.to_json
  when 'archive'
    contact[:stage] = 'passed'
    { success: true, action: "Archived" }.to_json
  else
    { success: false, error: 'Unknown action type' }.to_json
  end
end

# GET /news/contact/:id — contextual news for a specific contact/company
get '/news/contact/:id' do
  contact = $db[:contacts].find { |c| c[:id] == params[:id].to_i }
  halt 404, { error: 'Contact not found' }.to_json unless contact

  # In production, this would call NewsAPI, Crunchbase, Google News API
  # filtering by company name, founder name, and tags.
  # For now, return news items linked to this contact.
  news = ($db[:news] || []).select { |n| n[:contact_id] == contact[:id] }
    .sort_by { |n| n[:date] }.reverse

  {
    contact_id: contact[:id],
    company: contact[:company],
    news: news,
    sources: ['NewsAPI', 'Crunchbase', 'Google News', 'LinkedIn'],
    enrichment_note: "News detected by monitoring company name '#{contact[:company]}', founder '#{contact[:name]}', and tags #{contact[:tags].inspect}."
  }.to_json
end

# GET /news/portfolio — news for all portfolio companies
get '/news/portfolio' do
  portfolio = $db[:contacts].select { |c| c[:stage] == 'portfolio' }
  all_news = ($db[:news] || [])
  
  results = portfolio.map do |c|
    company_news = all_news.select { |n| n[:contact_id] == c[:id] }
      .sort_by { |n| n[:date] }.reverse
    { contact_id: c[:id], company: c[:company], news_count: company_news.size, news: company_news }
  end

  { portfolio_companies: results.size, total_news: results.sum { |r| r[:news_count] }, results: results }.to_json
end

# GET /analytics/overview — comprehensive analytics dashboard data
get '/analytics/overview' do
  active = $db[:contacts].reject { |c| c[:stage] == 'passed' }

  # Pipeline funnel
  by_stage = VALID_STAGES.each_with_object({}) { |s, h| h[s] = $db[:contacts].count { |c| c[:stage] == s } }

  # Tag distribution
  tag_counts = {}
  $db[:contacts].each { |c| c[:tags].each { |t| tag_counts[t] = (tag_counts[t] || 0) + 1 } }

  # Score distribution
  score_buckets = {
    'high_90_100' => active.count { |c| c[:score] >= 90 },
    'good_70_89'  => active.count { |c| c[:score] >= 70 && c[:score] < 90 },
    'mid_50_69'   => active.count { |c| c[:score] >= 50 && c[:score] < 70 },
    'low_0_49'    => active.count { |c| c[:score] < 50 },
  }

  # Health distribution
  health = { active: 0, warning: 0, critical: 0, dead: 0 }
  active.each { |c|
    days = (Date.today - Date.parse(c[:last_contact])).to_i rescue 999
    health[stale_level(days).to_sym] += 1
  }

  # Conversion rate
  portfolio_count = by_stage['portfolio'] || 0
  conversion = active.any? ? (portfolio_count.to_f / active.size * 100).round(1) : 0

  # Avg score
  avg_score = active.any? ? (active.sum { |c| c[:score] }.to_f / active.size).round(1) : 0

  # Pass rate
  total = $db[:contacts].size
  pass_rate = total > 0 ? ((by_stage['passed'] || 0).to_f / total * 100).round(1) : 0

  {
    total_deals: total,
    active_pipeline: active.size,
    conversion_rate: conversion,
    avg_score: avg_score,
    pass_rate: pass_rate,
    by_stage: by_stage,
    tag_distribution: tag_counts.sort_by { |_, v| -v }.to_h,
    score_distribution: score_buckets,
    health_distribution: health,
    # Simulated fund metrics (placeholder — in production from portfolio DB)
    fund_metrics: {
      tvpi: 2.4, dpi: 0.8, rvpi: 1.6, irr: 28.0, moic: 3.1
    }
  }.to_json
end

# GET /dealflow/stage-aging — average time contacts spend in each stage
get '/dealflow/stage-aging' do
  aging = VALID_STAGES.each_with_object({}) { |stage, h|
    contacts_in_stage = $db[:contacts].select { |c| c[:stage] == stage }
    if contacts_in_stage.any?
      avg_days = contacts_in_stage.sum { |c|
        (Date.today - Date.parse(c[:created_at])).to_i rescue 0
      }.to_f / contacts_in_stage.size
      h[stage] = { count: contacts_in_stage.size, avg_days: avg_days.round(1) }
    else
      h[stage] = { count: 0, avg_days: 0 }
    end
  }
  aging.to_json
end
