"""Current Space work stays visible, readable and absent when idle."""

import json
from pathlib import Path
import tempfile
import unittest

import support


@unittest.skipUnless(support.QS, 'Quickshell is required')
class SpaceActivityTests(unittest.TestCase):
    run_qml = support.run_qml

    def test_shared_card_and_panel_variants(self):
        self.run_qml("""import QtQuick
import QtTest
import Quickshell
import "spaces/movies"
import "spaces/streaming" as Streaming
FloatingWindow {
 id:root
 implicitWidth:1000;implicitHeight:700
 ArtworkCard {id:poster;x:20;y:20;width:180;height:300;text:"Poster";highlighted:true}
 Streaming.VideoCard {id:video;objectName:"fixtureVideo";x:250;y:20;width:320;height:260;selected:true;video:({title:"Fixture video",creator:"Creator",duration:125,localPath:"/fixture"})}
 MovieStyle.Panel {id:full;parent:root.contentItem;fullArea:true}
 MovieStyle.Panel {id:centered;parent:root.contentItem;maximumPanelWidth:600;maximumPanelHeight:400}
 TestCase {id:input;parent:root.contentItem;when:false}
 function check(value,message){if(!value)throw Error(message);}
 function find(item,name){if(item.objectName===name)return item;for(const child of item.children??[]){const found=find(child,name);if(found)return found;}return null;}
 Timer{interval:100;running:true;onTriggered:{try{
  const frame=find(video,"fixtureVideoImageFrame"),leading=find(video,"fixtureVideoLeadingBadge"),trailing=find(video,"fixtureVideoTrailingBadge");
  check(frame&&Math.abs(frame.width/frame.height-16/9)<.02,"video thumbnail is not widescreen");
  check(video.text==="Fixture video"&&video.subtitle==="Creator"&&leading.visible&&leading.label==="OFFLINE"&&trailing.visible&&trailing.label==="2:05","video metadata or badges were lost");
  video.video={title:"Live video",creator:"Creator",live:true,availability:"needs_auth"};
  check(leading.label==="SIGN-IN"&&trailing.label==="LIVE","live or sign-in badges were lost");
  video.video={title:"Audio",creator:"Creator",localPath:"/fixture",audio:true};check(leading.label==="AUDIO","audio badge was lost");
  check(video.background.radius===poster.background.radius&&video.background.color===poster.background.color&&video.background.border.width===poster.background.border.width,"video selection differs from artwork cards");
  video.selected=false;input.mouseMove(video,10,10);input.wait(30);check(video.hovered&&video.background.color===MovieStyle.accentSurface,"video hover differs from artwork cards");
  check(full.width===root.contentItem.width&&full.height===root.contentItem.height&&full.x===0&&full.y===0,"full panel does not fill its content area");
  centered.open();input.wait(20);
  check(centered.width===600&&centered.height===400&&centered.x===(root.contentItem.width-600)/2&&centered.y===(root.contentItem.height-400)/2,"centered panel geometry is wrong: "+[centered.width,centered.height,centered.x,centered.y,root.contentItem.width,root.contentItem.height]);
  check(full.padding===20&&centered.padding===20&&full.background.color===centered.background.color&&full.background.radius===centered.background.radius&&full.background.border.color===centered.background.border.color,"panel surfaces differ");
  centered.maximumPanelWidth=2000;centered.maximumPanelHeight=2000;input.wait(20);
  check(centered.width===root.contentItem.width-40&&centered.height===root.contentItem.height-40&&centered.x===20&&centered.y===20,"centered panel does not respect the edge inset");
  console.log("DISPLAY_PASS");Qt.quit();
 }catch(error){console.error("DISPLAY_FAIL",String(error));Qt.quit();}}}
 Timer{interval:5000;running:true;onTriggered:{console.error("DISPLAY_FAIL timeout");Qt.quit();}}
}""")

    def test_shared_search_favorite_and_primary_controls(self):
        self.run_qml("""import QtQuick
import QtTest
import Quickshell
import "spaces/movies"
FloatingWindow {
 id:root
 implicitWidth:600;implicitHeight:220
 property int clearedCount:0
 MovieInput {id:search;objectName:"search";x:20;y:20;width:240;clearable:true;onCleared:clearedCount++}
 MovieIconButton {id:favorite;x:20;y:90;favoriteControl:true;onClicked:favorite.favorite=!favorite.favorite}
 MovieButton {id:primary;x:100;y:90;text:"Watch";primary:true}
 SplitButton {id:split;objectName:"split";x:250;y:90;text:"Watch"}
 TestCase {id:input;parent:root.contentItem;when:false}
 function check(value,message){if(!value)throw Error(message);}
 function find(item,name){if(item.objectName===name)return item;for(const child of item.children??[]){const found=find(child,name);if(found)return found;}return null;}
 Timer{interval:100;running:true;onTriggered:{try{
  search.text="query";const clear=find(search,"searchClear");check(clear&&clear.visible,"search clear control missing");
  input.mouseClick(clear);check(!search.text&&clearedCount===1&&search.activeFocus,"search clear did not retain focus");
  check(!favorite.highlighted&&favorite.iconName==="star"&&favorite.text==="Add favorite","empty favorite state is wrong");
  input.mouseClick(favorite);check(favorite.highlighted&&favorite.iconName==="star-filled"&&favorite.text==="Remove favorite","selected favorite state is wrong");
  input.mouseMove(primary);input.wait(180);check(primary.hovered&&primary.background.color==MovieStyle.primaryColor(false,true),"primary hover style differs");const hoverColor=String(primary.background.color);
  const splitPrimary=find(split,"splitPrimary");input.mouseMove(splitPrimary);input.wait(180);
  check(String(splitPrimary.background.color)===hoverColor,"single and split primary hover colors differ");
  console.log("DISPLAY_PASS");Qt.quit();
 }catch(error){console.error("DISPLAY_FAIL",String(error));Qt.quit();}}}
 Timer{interval:5000;running:true;onTriggered:{console.error("DISPLAY_FAIL timeout");Qt.quit();}}
}""")

    def test_concurrent_progress_and_no_idle_or_hidden_history(self):
        self.run_qml("""import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import "spaces/movies"
FloatingWindow {
 id:root
 implicitWidth:500;implicitHeight:250
 property int stage:0
 ActivityIndicator {id:activity;x:30;y:30;spinnerName:"testSpinner"}
 TextField {id:field;x:30;y:120;width:220;height:40}
 TestCase {id:input;parent:root.contentItem;when:false}
 function check(value,message){if(!value)throw new Error(message);}
 function find(item,name,seen){
  if(!item)return null;seen=seen||new Set();if(seen.has(item))return null;seen.add(item);
  if(item.objectName===name)return item;
  for(const child of [...(item.children||[]),...(item.data||[])]){const found=find(child,name,seen);if(found)return found;}
  return null;
 }
 function hover(){input.mouseMove(root.contentItem,400,200);input.mouseMove(activity,14,14);}
 Timer{id:driver;interval:100;running:true;repeat:true;onTriggered:{driver.stop();try{
  const tip=find(activity,"spaceActivityTooltip"),spinner=find(activity,"testSpinner");
  if(stage===0){
   check(!activity.visible&&!activity.tooltipText,"idle indicator appeared");
   activity.tasks=[activity.task(true,"catalogue","Loading videos…"),activity.task(true,"details","Loading details…")];
   field.forceActiveFocus();hover();stage++;return;
  }
  if(stage===1){
   if(!tip.visible)return;
   check(spinner.running&&tip.text.includes("Loading videos")&&tip.text.includes("Loading details"),"concurrent tasks missing");
   check(field.activeFocus&&!tip.grabFocus,"activity tooltip took focus");
   activity.tasks=[activity.task(true,"details","Loading details…")];stage++;return;
  }
  if(stage===2){
   check(tip.text==="Loading details…","completed task remained in current work");
   activity.tasks=[];stage++;return;
  }
  if(stage===3){
   check(!activity.visible&&!spinner.running&&!tip.visible&&!activity.tooltipText,"idle completion or tooltip remained");
   activity.jobs=[{job_id:"one",title:"Save song",state:"running",detail:"Downloading",done:50,total:100},
                  {job_id:"two",title:"Analyze video",state:"queued",detail:"Queued",done:0,total:0}];
   hover();stage++;return;
  }
  if(stage===4){
   if(!tip.visible)return;
   check(spinner.running&&tip.text.includes("50%")&&tip.text.includes("Analyze video"),"concurrent job progress missing");
   activity.jobs=[{job_id:"one",title:"Save song",state:"finished",result:{message:"Saved to Music."}},
                  {job_id:"two",title:"Analyze video",state:"running",detail:"Analyzing"}];stage++;return;
  }
  if(stage===5){
   check(tip.text==="Analyze video · Analyzing","completed job remained in current work");
   activity.active=false;
   check(!activity.visible&&!spinner.running&&!activity.tooltipText,"hidden indicator kept animating or describing work");
   activity.jobs=[{job_id:"one",title:"Save song",state:"finished"},{job_id:"two",title:"Analyze video",state:"finished"}];stage++;return;
  }
  if(stage===6){activity.active=true;activity.jobs=activity.jobs.slice();stage++;return;}
  if(stage===7){
   check(!activity.visible&&!activity.busy&&!activity.tooltipText,"background completion reappeared on restore");
   activity.jobs=[{job_id:"fail",title:"Download",state:"failed",error:"Connection failed."},
                  {job_id:"cancel",title:"Download",state:"cancelled"}];stage++;return;
  }
  if(stage===8){
   check(!activity.visible&&!activity.tooltipText,"finished failures/cancellations remained in spinner");
   activity.jobs=[{id:"torrent",title:"Import movie",active:true,progress:0.4}];stage++;return;
  }
  if(stage===9){
   check(activity.visible&&activity.tooltipText.includes("40%"),"torrent progress missing");
   activity.jobs=[{id:"torrent",title:"Import movie",active:false,status:"review"}];stage++;return;
  }
  if(stage===10){
   check(!activity.visible&&!tip.visible&&!activity.tooltipText,"review status became idle history");
   console.log("DISPLAY_PASS");Qt.quit();
  }
 }catch(error){console.error("DISPLAY_FAIL",stage,error.message);Qt.quit();}finally{driver.restart();}}}
 Timer{interval:10000;running:true;onTriggered:{console.error("DISPLAY_FAIL timeout",stage);Qt.quit();}}
}""")

    def test_spinner_renders_red_after_becoming_busy(self):
        from PySide6.QtGui import QImage

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'spinner.png'
            self.run_qml(
                """import QtQuick
import Quickshell
import "spaces/movies"
FloatingWindow {
 implicitWidth:120;implicitHeight:100;color:"#09090b"
 property int stage:0
 Item {id:sample;anchors.fill:parent
  ActivityIndicator {id:activity;x:30;y:30}
 }
 Timer{id:driver;interval:250;running:true;repeat:true;onTriggered:{
  if(stage===0){activity.tasks=[activity.task(true,"work","Loading…")];stage++;return;}
  driver.stop();sample.grabToImage(result=>{result.saveToFile(OUTPUT);console.log("DISPLAY_PASS");Qt.quit();});
 }}
}""".replace('OUTPUT', json.dumps(str(path)))
            )
            image = QImage(str(path))
            self.assertFalse(image.isNull())
            red = sum(
                image.pixelColor(x, y).alpha() > 128
                and image.pixelColor(x, y).red() > 150
                and image.pixelColor(x, y).green() < 80
                and image.pixelColor(x, y).blue() < 80
                for x in range(30, 58)
                for y in range(30, 58)
            )
            self.assertGreater(
                red, 30, 'The active ring did not render with the Space accent color'
            )


if __name__ == '__main__':
    unittest.main()
