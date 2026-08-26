from pathlib import Path
import re

p = Path('VeloCutAI/VeloCutAI/VeloCutV4.swift')
s = p.read_text()

# Keep the original v0.4 UI and add only interaction state.
s = s.replace(
    '@State private var expandedLanes:Set<Int>=[]',
    '@State private var expandedLanes:Set<Int>=[]\n    @State private var timelineMagnificationBase:Double?'
)

# Wider zoom range while keeping the original +/- controls.
s = s.replace(
    'Button{model.timelineZoom=max(.55,model.timelineZoom-.2)}label:{Image(systemName:"minus.magnifyingglass")};Button{model.timelineZoom=min(3.2,model.timelineZoom+.2)}label:{Image(systemName:"plus.magnifyingglass")}',
    'Button{model.timelineZoom=max(0.35,model.timelineZoom-0.2)}label:{Image(systemName:"minus.magnifyingglass")};Button{model.timelineZoom=min(8.0,model.timelineZoom+0.2)}label:{Image(systemName:"plus.magnifyingglass")}'
)

# Give inline curve editing enough vertical room.
s = s.replace(
    'let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, videoH=46.0, curveH=34.0',
    'let pps=34.0*model.timelineZoom, center=geo.size.width/2, rulerH=22.0, fxH=42.0, videoH=46.0, curveH=56.0'
)

# Global Speed FX: keep the original block and add left/right resize handles.
fx_pattern = re.compile(r'^\s*ForEach\(model\.speedFX\)\{fx in .*$', re.M)
fx_replacement = '''            ForEach(model.speedFX){fx in
                let w=max(48,fx.duration*pps),x=center+(fx.start-model.projectTime)*pps+w/2
                SpeedFXBlock(
                    fx:fx,
                    width:w,
                    onOpen:{curveTarget = .global(fx.id)},
                    onMove:{model.moveSpeedFX(fx.id,delta:Double($0.width)/pps)},
                    onDuplicate:{model.duplicateSpeedFX(fx.id)},
                    onAtPlayhead:{model.duplicateSpeedFX(fx.id,atPlayhead:true)},
                    onRepeat:{model.repeatSpeedFX(fx.id,count:4)},
                    onDelete:{model.deleteSpeedFX(fx.id)}
                )
                .position(x:x,y:rulerH+fxH/2)

                SpeedFXEdgeHandleV4(
                    leading:true,
                    start:fx.start,
                    duration:fx.duration,
                    pps:pps,
                    onBegin:{model.beginInteractiveEdit()},
                    onChange:{newStart,newDuration in model.setSpeedFXStartInteractive(fx.id,start:newStart,duration:newDuration)}
                )
                .position(x:x-w/2+5,y:rulerH+fxH/2)

                SpeedFXEdgeHandleV4(
                    leading:false,
                    start:fx.start,
                    duration:fx.duration,
                    pps:pps,
                    onBegin:{model.beginInteractiveEdit()},
                    onChange:{_,newDuration in model.setSpeedFXDurationInteractive(fx.id,newDuration)}
                )
                .position(x:x+w/2-5,y:rulerH+fxH/2)
            }'''
s, count = fx_pattern.subn(fx_replacement, s, count=1)
if count != 1:
    raise RuntimeError('Speed FX timeline block was not found')

# Video clip: preserve card + long press/drag, add trim handles and editable speed curve under the clip.
clip_pattern = re.compile(r'^\s*ForEach\(Array\(model\.layouts\.enumerated\(\)\),id:\\\.element\.id\)\{index,l in .*$', re.M)
clip_replacement = '''            ForEach(Array(model.layouts.enumerated()),id:\\.element.id){index,l in
                let w=max(52,l.duration*pps),x=center+(l.start-model.projectTime)*pps+w/2,top=laneTop(l.clip.track)
                TimelineClipCardV4(
                    clip:l.clip,
                    index:index,
                    width:w,
                    selected:l.id==model.selectedClipID,
                    onTap:{model.selectClip(l.id)},
                    onMenu:{model.selectedClipID=l.id;contextClipID=l.id;clipDialog=true},
                    onMove:{model.moveClip(l.id,translation:$0,pps:pps)}
                )
                .position(x:x,y:top+videoH/2)

                if l.id == model.selectedClipID {
                    let sourcePerOutput = l.clip.sourceDuration / max(l.duration,0.01)
                    TimelineTrimHandleV4(
                        leading:true,
                        currentValue:l.clip.trimStart,
                        pps:pps,
                        sourcePerOutput:sourcePerOutput,
                        onBegin:{model.beginInteractiveEdit()},
                        onChange:{model.setTrimStartInteractive(l.id,$0)}
                    )
                    .position(x:x-w/2+6,y:top+videoH/2)

                    TimelineTrimHandleV4(
                        leading:false,
                        currentValue:l.clip.trimEnd,
                        pps:pps,
                        sourcePerOutput:sourcePerOutput,
                        onBegin:{model.beginInteractiveEdit()},
                        onChange:{model.setTrimEndInteractive(l.id,$0)}
                    )
                    .position(x:x+w/2-6,y:top+videoH/2)
                }

                if expandedLanes.contains(l.clip.track) {
                    InlineCurveEditorV4(
                        model:model,
                        target:.clip(l.id),
                        onOpen:{model.selectedClipID=l.id;curveTarget = .clip(l.id)}
                    )
                    .frame(width:w,height:curveH-5)
                    .position(x:x,y:top+videoH+curveH/2)
                }
            }'''
s, count = clip_pattern.subn(clip_replacement, s, count=1)
if count != 1:
    raise RuntimeError('Clip timeline block was not found')

# Existing one-finger drag remains project scrubbing/panning under the fixed playhead.
# Pinch is added simultaneously so the v0.4 timeline can zoom naturally with two fingers.
gesture_pattern = re.compile(r'^\s*\}\.clipped\(\)\.contentShape\(Rectangle\(\)\)\.gesture\(DragGesture\(minimumDistance:12\).*$', re.M)
gesture_replacement = '''        }
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance:2)
                .onChanged{v in
                    if timelineDragStart==nil { timelineDragStart=model.projectTime;model.beginScrub() }
                    model.scrub(to:(timelineDragStart ?? model.projectTime)-Double(v.translation.width)/pps)
                }
                .onEnded{_ in timelineDragStart=nil;model.endScrub()}
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged{value in
                    if timelineMagnificationBase==nil { timelineMagnificationBase=model.timelineZoom }
                    model.timelineZoom=min(8.0,max(0.35,(timelineMagnificationBase ?? model.timelineZoom)*Double(value)))
                }
                .onEnded{_ in timelineMagnificationBase=nil}
        )'''
s, count = gesture_pattern.subn(gesture_replacement, s, count=1)
if count != 1:
    raise RuntimeError('Timeline gesture block was not found')

# Replace only the v0.4 large curve editor UI. Preview and the rest of v0.4 stay untouched.
curve_pattern = re.compile(r'^struct CurveEditorPanel:View.*$', re.M)
curve_replacement = r'''struct CurveEditorPanel:View {
    @ObservedObject var model:EditorViewModel
    let target:CurveTarget
    let onClose:()->Void
    @State private var selectedPoint:UUID?

    var body:some View {
        VStack(spacing:10) {
            HStack {
                Button(action:onClose) { Image(systemName:"chevron.down.circle.fill").font(.title2) }
                VStack(alignment:.leading) {
                    Text(title).font(.headline)
                    Text("0.05× — 20× • playhead и точки синхронизированы с Preview").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    ForEach(SpeedCurvePreset.all) { p in Button(p.name) { model.applyPreset(p,to:target) } }
                } label: {
                    Label("Шаблон",systemImage:"sparkles").font(.caption)
                }
            }
            .padding(.horizontal,14)

            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    ForEach(SpeedCurvePreset.all) { p in
                        Button { model.applyPreset(p,to:target) } label: {
                            VStack(spacing:3) {
                                CurveThumbnail(curve:p.curve,lineWidth:1.5).frame(width:74,height:28)
                                Text(p.name).font(.system(size:8))
                            }
                            .padding(6)
                            .background(.thinMaterial,in:RoundedRectangle(cornerRadius:10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal,12)
            }

            VStack(spacing:4) {
                Slider(
                    value:Binding(
                        get:{model.normalizedPlayhead(for:target)},
                        set:{model.seekCurveTarget(target,normalized:$0)}
                    ),
                    in:0...1
                )
                HStack {
                    Text(timeText(0))
                    Spacer()
                    Text(timeText(model.normalizedPlayhead(for:target))).fontWeight(.semibold)
                    Spacer()
                    Text(timeText(1))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal,14)

            CurveEditorGraphV4(model:model,target:target,selectedPointID:$selectedPoint)
                .frame(minHeight:170)
                .padding(.horizontal,12)

            HStack {
                Button { model.addCurvePoint(target,t:model.normalizedPlayhead(for:target)) } label: { Label("Точка",systemImage:"plus.circle") }
                Button { model.mirrorCurve(target) } label: { Label("Mirror",systemImage:"arrow.left.and.right") }
                if let id=selectedPoint {
                    Button(role:.destructive) { model.deleteCurvePoint(target,pointID:id);selectedPoint=nil } label: { Image(systemName:"trash") }
                }
                Spacer()
                Picker("",selection:Binding(get:{model.curve(for:target).interpolation},set:{model.setCurveInterpolation(target,$0)})) {
                    ForEach(CurveInterpolation.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .font(.caption)
            .padding(.horizontal,14)

            if case .global(let id)=target,let fx=model.speedFX.first(where:{$0.id==id}) {
                VStack(spacing:8) {
                    HStack {
                        Text("Strength")
                        Slider(value:Binding(get:{fx.strength},set:{model.setSpeedFXStrength(id,$0)}),in:0...2)
                        Text("\(fx.strength,specifier:"%.1f")×").monospacedDigit()
                    }
                    HStack {
                        Text("Длина")
                        Slider(value:Binding(get:{fx.duration},set:{model.setSpeedFXDuration(id,$0)}),in:0.15...4)
                        Text("\(fx.duration,specifier:"%.2f")с").monospacedDigit()
                    }
                    HStack {
                        Picker("Режим",selection:Binding(get:{fx.mode},set:{model.setSpeedFXMode(id,$0)})) {
                            ForEach(SpeedFXMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Button { model.duplicateSpeedFX(id) } label: { Image(systemName:"plus.square.on.square") }
                        Button { model.repeatSpeedFX(id,count:4) } label: { Text("×4") }
                    }
                }
                .font(.caption)
                .padding(.horizontal,14)
            }
            Spacer(minLength:4)
        }
        .padding(.vertical,8)
        .background(.regularMaterial)
    }

    private var title:String {
        switch target {
        case .clip:return "Speed Curve клипа"
        case .global:return "Global Speed FX"
        }
    }

    private func timeText(_ normalized:Double)->String {
        String(format:"%.2fс",model.curveProjectTime(target,normalized:normalized))
    }
}'''
s, count = curve_pattern.subn(curve_replacement, s, count=1)
if count != 1:
    raise RuntimeError('Curve editor block was not found')

# Preserve the known successful v0.4 syntax normalization for Xcode 16.4.
s = s.replace('min(max(value, 0, ), 2)', 'min(max(value, 0), 2)')
s = re.sub(r'(?<![A-Za-z0-9_.])\.(\d+)', r'0.\1', s)
s = re.sub(r'(?<![<>=!+\-*/%&|^])\s*=\s*(?!=)', ' = ', s)
s = re.sub(r'(?<=[A-Za-z0-9_)])([+-])(?=0\.\d)', r' \1 ', s)
s = s.replace('drag=.zero', 'drag = .zero')
s = s.replace('c.videoGravity=.resizeAspect', 'c.videoGravity = .resizeAspect')
s = s.replace('session.outputFileType=.mp4', 'session.outputFileType = .mp4')

p.write_text(s)
print('Patched original v0.4 editor with timeline/curve interactions')
