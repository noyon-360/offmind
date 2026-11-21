import 'package:flutter_test/flutter_test.dart';
import 'package:offmind/services/llm_service.dart';

void main() {
  test('stripThinking removes reasoning blocks', () {
    expect(stripThinking('<think>hmm</think>Hello'), 'Hello');
    expect(stripThinking('<think>still thinking'), '');
    expect(stripThinking('Plain answer'), 'Plain answer');
  });
}
