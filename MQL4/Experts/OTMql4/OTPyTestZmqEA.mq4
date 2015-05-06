// -*-mode: c; c-style: stroustrup; c-basic-offset: 4; coding: utf-8-dos -*-

#property copyright "Copyright 2015 OpenTrading"
#property link      "https://github.com/OpenTrading/"
#property strict

#define INDICATOR_NAME          "PyTestZmqEA"

extern int iSEND_PORT=2027;
extern int iRECV_PORT=2028;
// can replace this with the IP address of an interface - not lo
extern string uBIND_ADDRESS="127.0.0.1";
extern string uStdOutFile="../../Logs/_test_PyTestZmqEA.txt";

#include <OTMql4/OTBarInfo.mqh>
/*
This provides the function sBarInfo which puts together the
information you want send to a remote client on every bar.
Change to suit your own needs.
*/
#include <OTMql4/OTBarInfo.mqh>

#include <OTMql4/OTLibLog.mqh>
#include <OTMql4/OTLibStrings.mqh>
//#include <OTMql4/OTZmqProcessCmd.mqh>
#include <OTMql4/OTLibPy27.mqh>
//unused #include <OTMql4/OTPyZmq.mqh>

int iTIMER_INTERVAL_SEC = 10;
int iCONTEXT = -1;
double fPY_ZMQ_CONTEXT_USERS = 0.0;

string uSYMBOL;
int iTIMEFRAME;
int iACCNUM;

int iTICK=0;
int iBAR=1;

int iIsEA=1;
string uCHART_ID="";
double fDebugLevel=0;

string uOTPyZmqProcessCmd(string uCmd) {
    return("");
}

#include <WinUser32.mqh>
void vPanic(string uReason) {
    "A panic prints an error message and then aborts";
    vError("PANIC: " + uReason);
    MessageBox(uReason, "PANIC!", MB_OK|MB_ICONEXCLAMATION);
    ExpertRemove();
}

string uSafeString(string uSymbol) {
    uSymbol = uStringReplace(uSymbol, "!", "");
    uSymbol = uStringReplace(uSymbol, "#", "");
    uSymbol = uStringReplace(uSymbol, "-", "");
    uSymbol = uStringReplace(uSymbol, ".", "");
    return(uSymbol);
}

int OnInit() {
    int iRetval;
    string uArg, uRetval;

    if (GlobalVariableCheck("fPyZmqContextUsers") == true) {
        fPY_ZMQ_CONTEXT_USERS=GlobalVariableGet("fPyZmqContextUsers");
    } else {
        fPY_ZMQ_CONTEXT_USERS = 0.0;
    }
    if (fPY_ZMQ_CONTEXT_USERS > 0.1) {
	iCONTEXT = MathRound(GlobalVariableGet("fPyZmqContext"));
	if (iCONTEXT < 1) {
	    vError("OnInit: unallocated context");
	    return(-1);
	}
        fPY_ZMQ_CONTEXT_USERS += 1.0;
    } else {
	iRetval = iPyInit(uStdOutFile);
	if (iRetval != 0) {
	    return(iRetval);
	}
	Print("Called iPyInit successfully");
	
	uSYMBOL=Symbol();
	iTIMEFRAME=Period();
	iACCNUM=AccountNumber();
    
	uArg="import zmq";
	vPyExecuteUnicode(uArg);
	// VERY IMPORTANT: if the import failed we MUST PANIC
	vPyExecuteUnicode("sFoobar = '%s : %s' % (sys.last_type, sys.last_value,)");
	uRetval=uPyEvalUnicode("sFoobar");
	if (StringFind(uRetval, "exceptions.SystemError", 0) >= 0) {
	    // Were seeing this during testing after an uninit 2 reload
	    uRetval = "PANIC: import zmq failed - we MUST restart Mt4:"  + uRetval;
	    vPanic(uRetval);
	    return(-2);
	}
	vPyExecuteUnicode("from OTMql427 import ZmqChart");
	//? add iACCNUM +"|" ? It may change during the charts lifetime
	uCHART_ID = uChartName(uSafeString(uSYMBOL), iTIMEFRAME, ChartID(), iIsEA);
	vPyExecuteUnicode(uCHART_ID+"=ZmqChart.ZmqChart('" +uCHART_ID +"', " +
			  "iSpeakerPort=" + iSEND_PORT + ", " +
			  "iListenerPort=" + iRECV_PORT + ", " +
			  "sIpAddress='" + uBIND_ADDRESS + "', " +
			  "iDebugLevel=" + MathRound(fDebugLevel) + ", " +
			  ")");
	vPyExecuteUnicode("sFoobar = '%s : %s' % (sys.last_type, sys.last_value,)");
	uRetval = uPySafeEval("sFoobar");
	if (StringFind(uRetval, "ERROR:", 0) >= 0) {
	    uRetval = "ERROR: ZmqChart.ZmqChart failed: "  + uRetval;
	    vPanic(uRetval);
	    return(-3);
	}
			  
	iCONTEXT = iPyEvalInt("id(ZmqChart.oCONTEXT)");
	GlobalVariableTemp("fPyZmqContext");
	GlobalVariableSet("fPyZmqContext", iCONTEXT);
	
        fPY_ZMQ_CONTEXT_USERS = 1.0;
	
    }
    GlobalVariableSet("fPyZmqContextUsers", fPY_ZMQ_CONTEXT_USERS);
    vDebug("OnInit: fPyZmqContextUsers=" + fPY_ZMQ_CONTEXT_USERS);

    EventSetTimer(iTIMER_INTERVAL_SEC);
    return (0);
}

/*
OnTimer is called every iTIMER_INTERVAL_SEC (10 sec.)
which allows us to use Python to look for Zmq inbound messages,
or execute a stack of calls from Python to us in Metatrader.
*/
void OnTimer() {
    string uRetval="";
    string uMessage;
    string uMess;

    /* timer events can be called before we are ready */
    if (GlobalVariableCheck("fPyZmqContextUsers") == false) {
      return;
    }
    iCONTEXT = MathRound(GlobalVariableGet("fPyZmqContext"));
    if (iCONTEXT < 1) {
	vWarn("OnTick: unallocated context");
        return;
    }

    // same as Time[0] - the bar time not the real time
    datetime tTime=iTime(uSYMBOL, iTIMEFRAME, 0);
    string sTime = TimeToStr(tTime, TIME_DATE|TIME_MINUTES) + " ";
    string uType = "timer";
	
    uMess = iACCNUM +"|" +uSYMBOL +"|" +iTIMEFRAME +"|" + sTime;

    uRetval = uPySafeEval(uCHART_ID+".eSendOnSpeaker('" +uType +"', '" +uMess +"')");
    if (StringFind(uRetval, "ERROR:", 0) >= 0) {
	uRetval = "ERROR: eSendOnSpeaker " +uType +" failed: "  + uRetval;
	vWarn("OnTimer: " +uRetval);
	return;
    }
    // the uRetval should be empty - otherwise its an error
    if (uRetval == "") {
	vDebug("OnTimer: " +uRetval);
    } else {
	vWarn("OnTimer: " +uRetval);
    }
    /*
      We listen on every timer as well as every tick
      to make sure the channel is still responsive 
      even when the market is closed or there is no connection.
    */
    vListen();
}

void vListen() {
    string uRetval, uMsg, uDeferMsg, uMess;
    string uType="retval";
    
    uMsg = uPySafeEval(uCHART_ID+".sRecvOnListener()");
    if (StringFind(uMsg, "ERROR:", 0) >= 0) {
	uMsg = "ERROR: sRecvOnListener " +" failed: "  + uMsg;
	vWarn("vListen: " +uMsg);
	return;
    }

    vDebug("vListen: got" +uMsg);
    // the uMsg may be empty - we are non-blocking
    if (uMsg == "") {
	uRetval = "";
    } else if (StringFind(uMsg, "exec", 0) == 0) {
	// execs are executed immediately and return a result on the wire
	// They're things that take less than a tick to evaluate
	//vTrace("Processing immediate exec message: " + uMsg);
	uRetval = uOTPyZmqProcessCmd(uMsg);
    } else if (StringFind(uMsg, "cmd", 0) == 0) {
	uDeferMsg = uMsg;
	uRetval = "";
    } else {
        vError("Internal error, not cmd or exec: " + uMsg);
	uRetval = "";
    }
	
    uRetval = uPySafeEval(uCHART_ID+".eSendOnListener('retval|" + uRetval +"')");
    if (StringFind(uRetval, "ERROR:", 0) >= 0) {
	uRetval = "ERROR: eSendOnListener " +" failed: "  + uRetval;
	vWarn("vListen: " +uRetval);
	return;
    }
    // unused: if uRetval != ""

    //? maybe should sleep a second here to let the REP go back?
    Sleep(1000);
    
    vTrace("Processing defered cmd message: " + uDeferMsg);
    uMess = uOTPyZmqProcessCmd(uDeferMsg);
    
    uRetval = uPySafeEval(uCHART_ID+".eSendOnSpeaker('" +uType +"', '" +uMess +"')");
    if (StringFind(uRetval, "ERROR:", 0) >= 0) {
	uRetval = "ERROR: eSendOnSpeaker " +uType +" failed: "  + uRetval;
	vWarn("vTick: " +uRetval);
	return;
    }
    // the uRetval should be empty - otherwise its an error
    if (uRetval == "") {
	vDebug("vTick: " +uRetval);
	//? maybe should sleep a second here to let the PUB go?
	Sleep(1000);
    } else {
	vWarn("vTick: " +uRetval);
    }
}
	
void OnTick() {
    static datetime tNextbartime;

    bool bNewBar=false;
    string uType;
    bool bRetval;
    string uInfo;
    string uMess, uRetval;

    fPY_ZMQ_CONTEXT_USERS=GlobalVariableGet("fPyZmqContextUsers");
    if (fPY_ZMQ_CONTEXT_USERS < 0.5) {
	vWarn("OnTick: no context users");
        return;
    }
    iCONTEXT = MathRound(GlobalVariableGet("fPyZmqContext"));
    if (iCONTEXT < 1) {
	vWarn("OnTick: unallocated context");
        return;
    }

    // same as Time[0]
    datetime tTime=iTime(uSYMBOL, iTIMEFRAME, 0);
    string sTime = TimeToStr(tTime, TIME_DATE|TIME_MINUTES) + " ";

    if (tTime != tNextbartime) {
        iBAR += 1; // = Bars - 100
	bNewBar = true;
	iTICK = 0;
	tNextbartime = tTime;
	uInfo = sBarInfo();
	uType = "bar";
    } else {
        bNewBar = false;
	iTICK += 1;
	uInfo = iTICK;
	uType = "tick";
    }

    uMess  = iACCNUM +"|" +uSYMBOL +"|" +iTIMEFRAME +"|" +Bid +"|" +Ask +"|" +uInfo +"|" +sTime;

    uRetval = uPySafeEval(uCHART_ID+".eSendOnSpeaker('" +uType +"', '" +uMess +"')");
    if (StringFind(uRetval, "ERROR:", 0) >= 0) {
	uRetval = "ERROR: eSendOnSpeaker " +uType +" failed: "  + uRetval;
	vWarn("OnTick: " +uRetval);
	return;
    }
    // the retval should be empty - otherwise its an error
    if (uRetval == "") {
	vDebug("OnTick: " +uRetval);
    } else {
	vWarn("OnTick: " +uRetval);
    }
    
    /*
      We listen on every timer as well as every tick
      to make sure the channel is still responsive 
      even when the market is closed or there is no connection.
    */
    vListen();
}

void OnDeinit(const int iReason) {
    //? if (iReason == INIT_FAILED) { return ; }
    EventKillTimer();
    
    fPY_ZMQ_CONTEXT_USERS=GlobalVariableGet("fPyZmqContextUsers");
    if (fPY_ZMQ_CONTEXT_USERS < 1.5) {
	iCONTEXT = MathRound(GlobalVariableGet("fPyZmqContext"));
	if (iCONTEXT < 1) {
	    vWarn("OnDeinit: unallocated context");
	} else {
	    vPyExecuteUnicode("ZmqChart.oCONTEXT.destroy()");
	    vPyExecuteUnicode("ZmqChart.oCONTEXT = None");
	}
	GlobalVariableDel("fPyZmqContext");

	GlobalVariableDel("fPyZmqContextUsers");
	vDebug("OnDeinit: deleted fPyZmqContextUsers");
	
	vPyDeInit();
    } else {
	fPY_ZMQ_CONTEXT_USERS -= 1.0;
	GlobalVariableSet("fPyZmqContextUsers", fPY_ZMQ_CONTEXT_USERS);
	vDebug("OnDeinit: decreased, value of fPyZmqContextUsers to: " + fPY_ZMQ_CONTEXT_USERS);
    }
    

}
