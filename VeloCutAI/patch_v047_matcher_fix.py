from pathlib import Path

p = Path('VeloCutAI/patch_v047_clean_ui.py')
s = p.read_text()
old = '''# Remove the top bar and separate playback row. Preview becomes the complete top area.
old_stack = 'ZStack{Color(uiColor:.systemGroupedBackground).ignoresSafeArea();VStack(spacing:0){topBar;preview.frame(height:min(335,max(215,root.size.height*0.34)));playback;if let target=curveTarget{CurveEditorPanel(model:model,target:target,onClose:{curveTarget=nil}).frame(maxHeight:.infinity)}else{timeline.frame(maxHeight:.infinity)};bottomBar}.frame(width:root.size.width,height:root.size.height,alignment:.top)}'
new_stack = 'ZStack{Color(uiColor:.systemGroupedBackground).ignoresSafeArea();VStack(spacing:0){preview.frame(height:min(390,max(255,root.size.height*0.42))).ignoresSafeArea(edges:.top);if let target=curveTarget{CurveEditorPanel(model:model,target:target,onClose:{curveTarget=nil}).frame(maxHeight:.infinity)}else{timeline.frame(maxHeight:.infinity)};bottomBar}.frame(width:root.size.width,height:root.size.height,alignment:.top)}'
if old_stack not in s:
    raise RuntimeError('v0.4.6 editor stack not found')
s = s.replace(old_stack, new_stack, 1)
'''
new = '''# Remove the top bar and separate playback row. Preview becomes the complete top area.
# Earlier patches can change Preview sizing/spacing, so only match the stable sequence.
stack_pattern = re.compile(
    r'topBar;preview\\.frame\\(height:.*?\\);playback;if let target=curveTarget',
    re.S
)
stack_replacement = 'preview.frame(height:min(390,max(255,root.size.height*0.42))).ignoresSafeArea(edges:.top);if let target=curveTarget'
s, count = stack_pattern.subn(stack_replacement, s, count=1)
if count != 1:
    raise RuntimeError('v0.4.6 editor stack sequence not found')
'''
if old not in s:
    raise RuntimeError('Old v0.4.7 stack matcher source not found')
p.write_text(s.replace(old, new, 1))
print('Relaxed v0.4.7 editor stack matcher')
