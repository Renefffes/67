import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canPlayChoices, choicesFor, extractCards, initialData, isGroundedQuestion, relevantNotes, sampleNotes, sourceFact, trueFalseAnswer, validateData } from '../src/study.ts';
test('turns real biology notes into distinct cards without losing the answers',()=>{const cards=extractCards(sampleNotes);assert.equal(cards.length,8);assert.match(cards[1].front,/Nucleus/);assert.match(cards[1].back,/DNA/);assert.ok(cards.every(c=>!c.known));});
test('supports natural notes and non-ASCII vocabulary',()=>{const c=extractCards('The nucleus is the control centre.\nÀ bientôt: See you soon.');assert.equal(c.length,2);assert.equal(c[0].back,'the control centre.');assert.match(c[1].front,/À bientôt/);});
test('AI question answers preserve both the source term and definition',()=>{
  const cards=extractCards('Venus: The hottest planet in our solar system.\nEarth: The planet we live on.\nÀ bientôt: See you soon.');
  assert.equal(sourceFact(cards[0]),'Venus: The hottest planet in our solar system.');
  assert.equal(sourceFact(cards[1]),'Earth: The planet we live on.');
  assert.equal(sourceFact(cards[2]),'À bientôt: See you soon.');
  const paragraph=extractCards('Plants use sunlight to make food.')[0];
  assert.equal(sourceFact(paragraph),'Plants use sunlight to make food.');
});
test('AI questions reject unrelated or unsupported content instead of replacing a source card',()=>{
  const venus='Venus: The hottest planet in our solar system.';
  assert.equal(isGroundedQuestion('What is the hottest planet in our solar system?',venus),true);
  assert.equal(isGroundedQuestion('What is Venus?',venus),true);
  assert.equal(isGroundedQuestion('What is the planet we live on?','Earth: The planet we live on.'),true);
  assert.equal(isGroundedQuestion('What is the best way to get a job?','À bientôt: See you soon.'),false);
  assert.equal(isGroundedQuestion('What is the hottest planet in the universe?',venus),false);
  assert.equal(isGroundedQuestion('What is the answer?',venus),false);
  assert.equal(isGroundedQuestion('Venus is a planet.',venus),false);
});
test('choice learning has one correct answer and no duplicate options',()=>{const cards=extractCards(sampleNotes);for(let i=0;i<20;i++){const options=choicesFor(cards[0],cards);assert.equal(options.length,4);assert.equal(options.filter(a=>a===cards[0].back).length,1);assert.equal(new Set(options).size,4);}});
test('never fabricates distractors when all answers are the same',()=>{const cards=extractCards('First thing: Identical answer.\nSecond thing: Identical answer.');assert.deepEqual(choicesFor(cards[0],cards),['Identical answer.']);});
test('choice-based games need at least two distinct answers',()=>{const cards=extractCards('First thing: Identical answer.\nSecond thing: Identical answer.');assert.equal(canPlayChoices([]),false);assert.equal(canPlayChoices(cards.slice(0,1)),false);assert.equal(canPlayChoices(cards),false);assert.equal(canPlayChoices(extractCards(sampleNotes)),true);});
test('true-or-false propositions can be true or false on any round',()=>{const cards=extractCards(sampleNotes);for(const card of cards){assert.equal(trueFalseAnswer(card,cards,()=>0),card.back);assert.notEqual(trueFalseAnswer(card,cards,()=>.99),card.back);}});
test('tutor retrieves relevant notes and declines unrelated questions',()=>{const deck=initialData().decks[0];assert.match(relevantNotes('What is the nucleus?',deck),/DNA/);assert.equal(relevantNotes('Who won Wimbledon?',deck),'');});
test('backup validates complete shape and rejects malformed content',()=>{const data=initialData();assert.ok(validateData(JSON.parse(JSON.stringify(data))));assert.ok(!validateData({...data,answers:-1}));assert.ok(!validateData({...data,decks:[{...data.decks[0],cards:[{front:'missing answer'}]}]}));assert.ok(!validateData({...data,version:2}));});
