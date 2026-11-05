// Deterministic safety policy for challenges. Runs on EVERY challenge before it is shown or voted on,
// whether it came from the AI or from the fallback library. It is context-aware (negation and fiction
// framing are understood) and it enforces Player boundaries independently of how the AI tagged a candidate.
//
// Limits (documented in docs/threat-model.md): English-only lexicons, and a regex policy cannot understand
// every possible phrasing. It is the first line of defence; the model-based reviewer and human moderation sit behind it.
import { cleanText } from './parse.ts';
import { THEMES, type Boundaries, type ChallengeDraft, type Theme } from './types.ts';

export interface PolicyResult { ok: boolean; reasons: string[] }

// A negation earlier in the same sentence ("without touching anything", "no fire") neutralises a match.
const NEG = /\b(?:no|not|never|without|don'?t|dont|do not|doesn'?t|avoid|nothing|instead of|rather than)\b[^.;]{0,30}$/;
// Mimed or narrated danger is fine ("mime driving a bus"). Only used for the physical-danger group.
const PRETEND = /\b(?:pretend\w*|mime\w*|miming|imaginary|imagine\w*|fictional|pitch\w*|narrat\w+|describe|story|speech|monologue|act out|as if|as though)\b[^.;]{0,40}$/;
// Stricter fiction framing, used where a real third party or a real place would be the risk.
const FICTION = /\b(?:imaginary|fictional|invented|made-?up|make-?believe|pretend\w*|mime\w*|miming|as if|as though)\b[^.;]{0,40}$/;

type Ctx = 'none' | 'neg' | 'neg+pretend' | 'neg+fiction';
interface Rule { id: string; re: RegExp; ctx: Ctx }

const rule = (id: string, src: string, ctx: Ctx): Rule => ({ id, re: new RegExp(src, 'g'), ctx });

const RULES: Rule[] = [
  rule('physical_danger', String.raw`\b(?:jump\w*|leap\w*|hang(?:s|ing)?|dangl\w+|climb\w*|balcon\w+|roof\w*|ledge|cliff\w*|bridge|ladder|windowsill|driv(?:e|es|ing)|steer\w*|car|cars|bike|bicycle|motorcycle|scooter|skateboard|traffic|crosswalk|road|roads|highway|fire|flames?|candles?|lighter|matches|burn\w*|stove|oven|boiling|scald\w*|knife|knives|blade\w*|razor\w*|scissors|sharp|needle\w*|axe|weapon\w*|gun|guns|pistol|firearm\w*|bomb\w*|explosi\w+|fireworks?|electric\w*|socket|swim\w*|dive|diving|underwater|submerge\w*|drown\w*|hold(?:ing)? (?:your )?breath|chok\w+|faint\w*|pass(?:ing)? out|dizzy|spin(?:ning)? (?:until|around)|blindfold\w*|stunt\w*|parkour|backflip|cartwheel|handstand|headstand|acrobat\w*|sprint\w*|marathon|exhaust\w*|push-?ups?|burpees?|squats?|plank|dangerous|ice bath)\b`, 'neg+pretend'),
  rule('consumption', String.raw`\b(?:drink\w*|chug\w*|gulp\w*|swallow\w*|eat|eats|eating|ate|taste\w*|lick\w*|bite|bites|biting|sip\w*|shots?|devour\w*|munch\w*|chew\w*|spicy|pepper|hot sauce|swill\w*)\b`, 'neg'),
  rule('substances', String.raw`\b(?:alcohol\w*|beer|wine|vodka|whisk(?:e)?y|liquor|cocktail\w*|booze|drunk|tipsy|hangover|weed|cannabis|marijuana|cocaine|heroin|meth|drugs?|narcotic\w*|pills?|vape\w*|cigarette\w*|cigar\w*|smok(?:e|es|ing)|tobacco|opioid\w*|overdos\w*)\b`, 'neg'),
  rule('sexual_content', String.raw`\b(?:sex\w*|erotic\w*|nude|naked|nudity|strip\w*|undress\w*|lingerie|underwear|bra|boobs?|breasts?|butt|buttocks|twerk\w*|lap dance|seduc\w*|kiss\w*|make ?out|moan\w*|fetish\w*|porn\w*|horny|aroused|thirst trap|sensual\w*|sultry)\b`, 'none'),
  rule('physical_contact', String.raw`\b(?:touch\w*|hug\w*|grab\w*|slap\w*|punch\w*|kick\w*|hit|hits|hitting|tickl\w*|spank\w*|wrestl\w*|tackl\w*|push|shov\w+|pinch\w*|hold hands|massag\w*)\b`, 'neg'),
  rule('third_party', String.raw`\b(?:strangers?|passers?-?by|neighbou?rs?|co-?workers?|colleagues?|boss|bosses|customers?|waiters?|waitress\w*|barista\w*|cashier\w*|shopkeeper\w*|someone else|another person|other people|a friend|your friends?|your (?:mom|mum|mother|dad|father|sister|brother|partner|spouse|wife|husband|ex|roommate|flatmate|family|parents?|girlfriend|boyfriend)|family members?|real person|real people|someone you know|somebody|someone|anyone you know|phone call|call (?:a|your)|text (?:a|your|someone)|message (?:a|your|someone)|knock\w*|doorbell|door-?to-?door|approach\w*|walk up to|go up to|ask (?:a|an|someone|people|anyone)|follow\w*|stalk\w*|photograph\w*|film(?:ing)? (?:someone|people|a|your)|record(?:ing)? (?:someone|people|a|your))\b`, 'neg+fiction'),
  rule('personal_info', String.raw`\b(?:home address|email address|ip address|phone number|password\w*|pin code|credit card|bank\w*|passport|social security|ssn|salary|income|medical|diagnos\w+|medication\w*|real name|full name|id card|license plate|where you live|where you work|workplace|employer|birthday|birth date|date of birth|your age|how old)\b`, 'neg+fiction'),
  rule('sensitive_topic', String.raw`\b(?:religio\w+|politic\w+|election\w*|vote for|god|gods|jesus|allah|prophet|nazi\w*|hitler|terroris\w+|war crime\w*|celebrit\w+|famous (?:person|people|actor|singer)|president|prime minister|senator|brands?|logo|trademark|copyright\w*|lyrics|disney|marvel)\b`, 'neg'),
  rule('violence_harassment', String.raw`\b(?:kill\w*|murder\w*|stab\w*|shoot\w*|strangl\w*|torture\w*|suicid\w*|self-?harm\w*|cut yourself|hurt\w*|harm\w*|injur\w*|bleed\w*|blood\w*|bull(?:y|ies|ied|ying)|humiliat\w+|degrad\w+|shame\w*|insult\w*|mock\w*|roast\w*|harass\w*|abus\w+|threat\w*|racis\w+|sexis\w+|homophob\w*|transphob\w*|slur\w*|hate\w*|offend\w*|starv\w*|purg\w*|diet\w*|body-?shame|punish\w*|cry|cries|crying|beg|begs|begging|vomit\w*|puke|pain\w*)\b`, 'neg'),
  rule('minors', String.raw`\b(?:child\w*|kids?|teen\w*|minors?|underage|school\w*|students?|boy|boys|girl|girls|baby|babies|toddler\w*|juvenile\w*|classroom|playground)\b`, 'neg'),
  rule('illegal_activity', String.raw`\b(?:steal\w*|stole|theft|shoplift\w*|trespass\w*|vandal\w*|graffiti|pickpocket\w*|illegal\w*|crimes?|criminal\w*|break(?:ing)? into|burglar\w*|rob|robbery|fake (?:id|emergency|bomb|threat|ticket)|impersonat\w+|police|cops?|officer|911|emergency (?:number|call|services)|fraud\w*|scam\w*|forg(?:e|ery)|hack\w*|bribe\w*|smuggl\w*|counterfeit\w*|arson|prank call)\b`, 'neg'),
  rule('leaves_the_room', String.raw`\b(?:outside|outdoors?|go out|leave (?:the|your) (?:room|house|home|apartment|building)|public|publicly|park|mall|store|shop|supermarket|cafe|restaurant|bar|club|gym|street|rooftop|subway|metro|bus|train|station|airport|beach|forest|mountain|lake|pool|river|sea|ocean)\b`, 'neg+fiction'),
  rule('coercion', String.raw`\b(?:must continue|cannot (?:stop|quit|pass|skip|refuse)|can'?t (?:stop|quit|pass|skip|refuse)|may not (?:stop|quit|pass|skip)|no matter what|at all costs|until (?:you|they|he|she) (?:cry|vomit|faint|beg|drop|collapse|scream|break|give up|quit)|forc(?:e|ed|es|ing)|compel\w*|obey|mandatory|no excuses|or else|no backing out|forfeit\w*|penalty|lose points)\b`, 'none'),
  rule('prompt_injection', String.raw`(?:\b(?:ignore|disregard|forget|override|bypass)\b[^.]{0,20}\b(?:previous|prior|above|all|earlier|your)\b|system prompt|as an ai|language model|developer mode|jailbreak|you are now|new instructions|instructions? (?:above|below)|\[\/?inst\]|\bsystem:|\bassistant:|\bprompt\b|\bjson\b|\bapi\b)`, 'none'),
  rule('links_or_contact', String.raw`(?:https?:|www\.|\.[a-z]{2,}\/|[a-z0-9._%+-]+@[a-z0-9.-]+|@\w+|\+?\d[\d\s().-]{7,}\d|#\w+)`, 'none'),
];

// Extra rules for dares meant for teens (16-17). Only applied when the boundaries carry audience 'teen' (set by the server).
// They target what is specifically risky for this age: pressure and humiliation, meeting people, body image, going public
// on other platforms, and money. Same negation handling as above, so "no embarrassing dares" is not a hit.
const TEEN_RULES: Rule[] = [
  rule('teen_humiliation', String.raw`\b(?:embarrass\w*|cringe\w*|chicken|cowards?|wimps?|losers?|pathetic|dumb|stupid|idiot\w*|prove (?:yourself|you|that you)|peer pressure|everyone (?:is|else is) doing|dare you|double dare)\b`, 'neg'),
  rule('teen_meeting_people', String.raw`\b(?:meet(?:ing)? (?:up|someone|a stranger|in person|irl)|alone|after dark|late at night|at night|midnight|sneak\w*|secret(?:ly)?|behind (?:their|your) (?:back|parents)|without (?:telling|asking)|don'?t tell|keep (?:it|this) (?:a )?secret)\b`, 'neg'),
  rule('teen_body_image', String.raw`\b(?:weight|diet\w*|calories?|fat|skinny|ugly|body shap\w+|six-?pack|abs|attractive|sexy|hot|rate (?:your|my|their) (?:looks|body|face))\b`, 'neg'),
  rule('teen_going_public', String.raw`\b(?:post\w* (?:it )?(?:online|publicly)|go(?:ing)? viral|followers?|subscribers?|tag (?:someone|a friend|them)|livestream\w*|dm|dms|direct messages?|instagram|tiktok|snapchat|youtube|twitch|discord|whatsapp|telegram)\b`, 'neg'),
  rule('teen_money', String.raw`\b(?:pay|paid|buy|bought|spend|spent|money|cash|dollars?|euros?|bets?|wager\w*|gambl\w+|lottery|raffle|loot ?box\w*|gift\w*|donat\w+|tips?)\b`, 'neg'),
];

// Themes a Player may exclude. If the TEXT matches, the theme is present no matter how the AI tagged it.
const THEME_LEX: Record<Theme, RegExp> = {
  singing: /\b(?:sing\w*|song\w*|chorus|lyric\w*|hum|humming|melody|opera\w*|aria|rap|rapping|karaoke|jingle\w*|serenad\w*|tune)\b/,
  dancing: /\b(?:danc\w*|choreograph\w*|twirl\w*|waltz|moonwalk\w*|groove)\b/,
  romance: /\b(?:romanc\w*|romantic|flirt\w*|love (?:letter|confession|poem|song)|valentine\w*|crush|dating|proposal|wedding|marry|marriage|adore\w*|heartbreak\w*)\b/,
  food_props: /\b(?:food\w*|snack\w*|fruits?|vegetables?|cook\w*|recipes?|chefs?|menu|restaurants?|pizza|sandwich\w*|bread|cheese|cake|chocolate|coffee|tea|soup|sauce|meals?|dinner|lunch|breakfast|kitchen|banana|apple|potato\w*)\b/,
  accents: /\b(?:accents?|dialects?|brogue|drawl)\b/,
  public_speaking: /\b(?:speech\w*|keynote|toast|presentations?|monologue\w*|closing argument|lecture\w*|podcast|ted talk|address(?:ing)? the)\b/,
  dark_humor: /\b(?:villain\w*|funeral\w*|doom\w*|apocalyp\w*|haunt\w*|ghost\w*|curse\w*|grim|morbid|death|dead|dying|graveyard|zombie\w*|vampire\w*|demon\w*)\b/,
  physical_comedy: /\b(?:slapstick|pratfall\w*|stumbl\w*|trip|tripping|silly walk\w*|mime\w*|miming|exaggerated (?:movement|gesture)\w*|clown\w*|grimac\w*|funny walk)\b/,
  role_play: /\b(?:role-?play\w*|pretend\w*|characters?|persona\w*|in the role of|play(?:ing)? the part|play(?:ing)? an?|act(?:ing)? as|become an?|becomes an?|hero|detective|tour guide|narrator|anchor)\b/,
  trivia_pressure: /\b(?:quiz\w*|trivia|riddles?|puzzles?|countdown|count backwards?|mental math|multiply|memori[sz]\w*|spell\w*|alphabet|name as many|how many)\b/,
};

const NON_LATIN = /[^\x20-\x7E\u2018\u2019\u201C\u201D\u2013\u2014\u2026]/;
const BRACKETS = /[<>{}\[\]\\|^~`]/;

function hitsRule(text: string, r: Rule): boolean {
  r.re.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = r.re.exec(text)) !== null) {
    if (m[0].length === 0) { r.re.lastIndex++; continue; }
    const sentenceStart = Math.max(text.lastIndexOf('.', m.index), text.lastIndexOf(';', m.index), text.lastIndexOf('!', m.index), text.lastIndexOf('?', m.index));
    const before = text.slice(Math.max(sentenceStart + 1, m.index - 60), m.index);
    if (r.ctx !== 'none' && NEG.test(before)) continue;
    if (r.ctx === 'neg+pretend' && PRETEND.test(before)) continue;
    if (r.ctx === 'neg+fiction' && FICTION.test(before)) continue;
    return true;
  }
  return false;
}

export function challengeText(d: Pick<ChallengeDraft, 'title' | 'objective' | 'completionCriteria'>): string {
  return cleanText([d.title, d.objective, ...d.completionCriteria].join('. ')).toLowerCase();
}

export function checkPolicy(d: ChallengeDraft, b: Boundaries): PolicyResult {
  const reasons: string[] = [];
  const raw = [d.title, d.objective, ...d.completionCriteria].join(' ');
  const text = challengeText(d);

  if (NON_LATIN.test(cleanText(raw))) reasons.push('unsupported_characters');
  if (BRACKETS.test(raw)) reasons.push('markup_characters');
  if (/\S{26,}/.test(text)) reasons.push('suspicious_token');

  for (const r of RULES) if (hitsRule(text, r)) reasons.push(r.id);
  if (b.audience === 'teen') for (const r of TEEN_RULES) if (hitsRule(text, r)) reasons.push(r.id);

  // Player boundaries: enforced here, on the server, no matter what the AI claims.
  if (b.excludedCategories.includes(d.category)) reasons.push('boundary:category');
  if (d.difficulty > b.maxDifficulty) reasons.push('boundary:difficulty');
  for (const t of d.tags) if (b.excludedThemes.includes(t)) reasons.push(`boundary:theme:${t}`);
  for (const t of THEMES) if (b.excludedThemes.includes(t) && THEME_LEX[t].test(text)) reasons.push(`boundary:theme:${t}`);

  const uniq = [...new Set(reasons)];
  return { ok: uniq.length === 0, reasons: uniq };
}

const STOP = new Set(['the', 'a', 'an', 'of', 'to', 'and', 'in', 'on', 'for', 'as', 'with', 'that', 'is', 'it', 'your', 'you', 'at', 'by']);
const tokens = (s: string) => new Set(s.toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(' ').filter((w) => w.length > 2 && !STOP.has(w)));

/** Token-overlap similarity of two challenges (0..1). Used to drop near-duplicates in a set of five. */
export function similarity(a: Pick<ChallengeDraft, 'title' | 'objective'>, b: Pick<ChallengeDraft, 'title' | 'objective'>): number {
  const x = tokens(`${a.title} ${a.objective}`), y = tokens(`${b.title} ${b.objective}`);
  if (!x.size || !y.size) return 0;
  let inter = 0;
  for (const w of x) if (y.has(w)) inter++;
  return inter / (x.size + y.size - inter);
}
