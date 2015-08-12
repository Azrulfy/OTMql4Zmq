# -*-mode: python; py-indent-offset: 4; indent-tabs-mode: nil; encoding: utf-8-dos; coding: utf-8 -*-

"""
This module can be run from the command line to test ZeroMQ
by listening to the broker for messages sent by a speaker
such as ZmqChart.py. For example, to see bars and timer topics do:
  python ZmqListener.py -v 4 bar timer
The known topics are: bar tick timer retval, and no options means listen for all.

Give  --help to see the options.
"""

import sys, logging
import time
import traceback

import zmq

from OTLibLog import vError, vWarn, vInfo, vDebug, vTrace
oLOG = logging

class ZmqMixin(object):
    oContext = None

    def __init__(self, sChartId, **dParams):
        self.dParams = dParams
        self.sChartId = sChartId
        if self.oContext is None:
            self.oContext = zmq.Context()
        self.oSubPubSocket = None
        self.oReqRepSocket = None
        self.iDebugLevel = dParams.get('iDebugLevel', 4)
        self.iSubPubPort = dParams.get('iSubPubPort', 2027)
        self.iReqRepPort = dParams.get('iReqRepPort', 2028)
        self.sHostAddress = dParams.get('sHostAddress', '127.0.0.1')

    def eBindToSub(self):
        return self.eBindToSubPub(zmq.SUB)
    
    def eBindToPub(self):
        return self.eBindToSubPub(zmq.PUB)
    
    def eBindToSubPub(self, iDir=zmq.PUB):
        """
        We bind on this Metatrader end, and connect from the scripts.
        This is called by Metatrader.
        """
        if self.oSubPubSocket is None:
            assert iDir in [zmq.PUB, zmq.SUB]
            oSubPubSocket = self.oContext.socket(iDir)
            assert oSubPubSocket, "eBindToSub: oSubPubSocket is null"
            assert self.iSubPubPort, "eBindToSub: iSubPubPort is null"
            sUrl = 'tcp://%s:%d' % (self.sHostAddress, self.iSubPubPort,)
            vInfo("eBindToSub: Binding to SUB " +sUrl)
            sys.stdout.flush()
            oSubPubSocket.bind(sUrl)
            time.sleep(0.1)
            self.oSubPubSocket = oSubPubSocket

    def eConnectToSubPub(self, lTopics, iDir=zmq.SUB):
        """
        We bind on this Metatrader end, and connect from the scripts.
        This is called by the scripts.
        """

        if self.oSubPubSocket is None:
            assert iDir in [zmq.PUB, zmq.SUB]
            oSubPubSocket = self.oContext.socket(iDir)
            s = self.sHostaddress +":"+str(self.iSubPubPort)
            oSubPubSocket.connect("tcp://"+s)
            self.oSubPubSocket = oSubPubSocket
            if iDir == zmq.SUB:
                if self.iDebugLevel >= 1:
                    vInfo("Subscribing to: " + s +" with topics " +repr(lTopics))
                for sElt in lTopics:
                    self.oSubPubSocket.setsockopt(zmq.SUBSCRIBE, sElt)
            else:
                if self.iDebugLevel >= 1:
                    vInfo("Publishing to: " + s)

        return ""

    def eConnectToReq(self):
        return self.eConnectToReqRep(iDir=zmq.REQ)

    def eConnectToRep(self):
        return self.eConnectToReqRep(iDir=zmq.REP)

    def eConnectToReqRep(self, iDir):
        """
        We bind on our Metatrader end, and connect from the scripts.
        """
        if self.oReqRepSocket is None:
            assert iDir in [zmq.REP, zmq.REQ]
            oReqRepSocket = self.oContext.socket(iDir)
            assert oReqRepSocket, "eConnectToReqRep: oReqRepSocket is null"
            assert self.iReqRepPort, "eConnectToReqRep: iReqRepPort is null"
            sUrl = 'tcp://%s:%d' % (self.sHostAddress, self.iReqRepPort,)
            vInfo("eConnectToReqRep: Connecting to %d: %s" % (iDir, sUrl,))
            sys.stdout.flush()
            oReqRepSocket.connect(sUrl)
            self.oReqRepSocket = oReqRepSocket
        return ""

    def eBindToReq(self):
        return eBindToReqRep(self, iDir=zmq.REQ)

    def eBindToRep(self):
        return eBindToReqRep(self, iDir=zmq.REP)

    def eBindToReqRep(self, iDir=zmq.REP):
        """
        We bind on our Metatrader end, and connect from the scripts.
        """
        assert iDir in [zmq.REP, zmq.REQ]
        if self.oReqRepSocket is None:
            oReqRepSocket = self.oContext.socket(iDir)
            assert oReqRepSocket, "eBindToReqRep: oReqRepSocket is null"
            assert self.iReqRepPort, "eBindToReqRep: iReqRepPort is null"
            sUrl = 'tcp://%s:%d' % (self.sHostAddress, self.iReqRepPort,)
            vInfo("eBindToReqRep: Binding to %d: %s" % (iDir, sUrl,))
            sys.stdout.flush()
            oReqRepSocket.bind(sUrl)
            self.oReqRepSocket = oReqRepSocket

    def sRecvOnSubPub(self, iFlags=zmq.NOBLOCK):
        if self.oSubPubSocket is None:
            # was self.eBindListener()
            # needs lTopics: self.eConnectToSubPub(lTopics)
            pass
        assert self.oSubPubSocket, "sRecvOnSubPub: oSubPubSocket is null"
        try:
            sRetval = self.oSubPubSocket.recv(flags=iFlags)
        except zmq.ZMQError as e:
            # zmq4: iError = zmq.zmq_errno()
            iError = e.errno
            if iError == zmq.EAGAIN:
                #? This should only occur if iFlags are zmq.NOBLOCK
                time.sleep(1.0)
            else:
                vWarn("sRecvOnSubPub: ZMQError in Recv listener: %d %s" % (
                    iError, zmq.strerror(iError),))
                sys.stdout.flush()
            sRetval = ""
        except Exception as e:
            vError("sRecvOnSubPub: Failed Recv listener: " +str(e))
            sys.stdout.flush()
            sRetval = ""
        return sRetval

    def eReturnOnSpeaker(self, sTopic, sMsg, sOrigin=None):
        return self.eSendOnSpeaker(sTopic, sMsg, sOrigin)

    def eSendOnSpeaker(self, sTopic, sMsg, sOrigin=None):
        assert sMsg.startswith(sTopic)
        if sOrigin:
	    # This message is a reply in a cmd
            lOrigin = sOrigin.split("|")
            assert lOrigin[0] in ['exec', 'cmd'], "eSendOnSpeaker: lOrigin[0] in ['exec', 'cmd'] " +repr(lOrigin)
            sMark = lOrigin[3]
            lMsg = sMsg.split("|")
            assert lMsg[0] == 'retval', "eSendOnSpeaker: lMsg[0] in ['retval'] " +repr(lMsg)
            lMsg[3] = sMark
	    # Replace the mark in the reply with the mark in the cmd
            sMsg = '|'.join(lMsg)

        if self.oSubPubSocket is None:
            self.eBindToPub()
        assert self.oSubPubSocket, "eSendOnSpeaker: oSubPubSocket is null"
        self.oSubPubSocket.send(sMsg)
        return ""

    def eSendOnReqRep(self, sTopic, sMsg):
        assert sMsg.startswith(sTopic)
        assert self.oReqRepSocket, "eSendOnReqRep: oReqRepSocket is null"
        try:
            sRetval = self.oReqRepSocket.send(sMsg)
        except zmq.ZMQError as e:
            # iError = zmq.zmq_errno()
            iError = e.errno
            if iError == zmq.EAGAIN:
                time.sleep(1.0)
                sRetval = ""
            else:
                sRetval = zmq.strerror(iError)
                vWarn("eSendOnReqRep: ZMQError: %d %s" % (
                    iError, sRetval,))
                sys.stdout.flush()
        except Exception as e:
            vError("eSendOnReqRep: Failed: " +str(e))
            sys.stdout.flush()
            sRetval = str(e)
        return sRetval

    def sRecvOnReqRep(self):
        if self.oReqRepSocket is None:
            self.eBindToRep()
        assert self.oReqRepSocket, "sRecvOnReqRep: oReqRepSocket is null"
        try:
            sRetval = self.oReqRepSocket.recv(flags=zmq.NOBLOCK)
        except zmq.ZMQError as e:
            # iError = zmq.zmq_errno()
            iError = e.errno
            if iError == zmq.EAGAIN:
                time.sleep(1.0)
            else:
                vWarn("sRecvOnReqRep: ZMQError in Recv listener: %d %s" % (
                    iError, zmq.strerror(iError),))
                sys.stdout.flush()
            sRetval = ""
        except Exception as e:
            vError("sRecvOnReqRep: Failed Recv listener: " +str(e))
            sys.stdout.flush()
            sRetval = ""
        return sRetval

    def eReturnOnReqRep(self, sTopic, sMsg, sOrigin=None):
        # we may send back null strings
        if sOrigin and sMsg and sMsg != "null":
	    # This message is a reply in a cmd
            lOrigin = sOrigin.split("|")
            assert lOrigin[0] in ['exec', 'cmd'], "eReturnOnReqRep: lOrigin[0] in ['exec', 'cmd'] " +repr(lOrigin)
            sMark = lOrigin[3]
            lMsg = sMsg.split("|")
            assert lMsg[0] == 'retval', "eReturnOnReqRep: lMsg[0] in ['retval'] " +repr(lMsg)
            lMsg[3] = sMark
	    # Replace the mark in the reply with the mark in the cmd
            sMsg = '|'.join(lMsg)

        assert self.oReqRepSocket, "eReturnOnReqRep: oReqRepSocket is null"
        self.oReqRepSocket.send(sMsg)
        return ""

    def bCloseContextSockets(self):
        """
        same
        """
        if self.oReqRepSocket:
            self.oReqRepSocket.setsockopt(zmq.LINGER, 0)
            time.sleep(0.1)
            self.oReqRepSocket.close()
        if self.oSubPubSocket:
            self.oSubPubSocket.setsockopt(zmq.LINGER, 0)
            time.sleep(0.1)
            self.oSubPubSocket.close()
        if self.iDebugLevel >= 1:
            vInfo("destroying the context")
        sys.stdout.flush()
        time.sleep(0.1)
        self.oContext.destroy()
        self.oContext = None
        return True
    bCloseConnectionSockets = bCloseContextSockets

if __name__ == '__main__':
    # OTZmqSubscribe is in OTMql4Zmq/bin
    from OTZmqSubscribe import iMain as iOTZmqSubscribeMain
    sys.exit(iOTZmqSubscribeMain())

