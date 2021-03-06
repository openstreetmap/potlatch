
	// =====================================================================================
	// History functions

	function getHistory() {
		if      (_root.poiselected>0)    { remote_read.call('getnode_history',historyresponder,Number(_root.poiselected)); }
		else if (_root.pointselected>=0) { var n=_root.ws.path[_root.pointselected].id;
										   if (n>0) { remote_read.call('getnode_history',historyresponder,n); } }
		else if (_root.wayselected>0)    { remote_read.call('getway_history' ,historyresponder,Number(_root.wayselected)); };
	};

	// Responder when AMF returns history of way/node

	historyresponder = function() { };
	historyresponder.onResult = function(result) {
		_root.reverttype=result[0];		// 'node' or 'way'
		_root.revertid  =result[1];		// id

		// Draw window
		
		_root.windows.attachMovie("modal","history",++windowdepth);
		_root.windows.history.init(375,90,new Array(iText('more'),iText('cancel')),handleHistoryChoice);
		_root.windows.history.box.createTextField("prompt",2,7,9,250,100);
		writeText(_root.windows.history.box.prompt,iText('prompt_revertversion'));
		adjustTextField(_root.windows.history.box.prompt);

		_root.windows.history.box.createEmptyMovieClip('revert' ,21);
		_root.windows.history.box.createEmptyMovieClip('contact',22);
		drawButton(_root.windows.history.box.revert , 9,60,iText('revert'),"");
		_root.windows.history.box.revert.onPress=doRevert;
		drawButton(_root.windows.history.box.contact,69,60,iText('mail'),"");
		_root.windows.history.box.contact.onPress=doMail;

		with (_root.windows.history.box) {
			lineStyle(1,0x7F7F7F,100);
			moveTo(137,62); lineTo(137,75);
		}

		// Assemble list

		var versionlist=new Array();
		_root.versioninfo=result[2];
		if (Stage.height<versioninfo.length*16) {
			// too many entries, so trim the list
			var a=Math.floor((versioninfo.length+2)*16/Stage.height);
			var i=0;
			while (i<versioninfo.length) {
				versioninfo.splice(i,a); i++;
			}
		}
		for (i=0; i<versioninfo.length; i+=1) {
			versionlist.push(versioninfo[i][0]+' ('+versioninfo[i][1]+')');
		}
		_root.windows.history.box.attachMovie("menu","version",23);
		_root.windows.history.box.version.init(9,32,0,versionlist,
			iText('tip_revertversion'),
			function(n) {
				var a=100; if (versioninfo[n][2]==0) { var a=25; }
				_root.windows.history.box.revert._alpha=a;
				_root.reverttime   =versioninfo[n][0]; 
				_root.revertauthor =versioninfo[n][2];
				_root.revertname   =versioninfo[n][1];
			},null,356);
		_root.reverttime  =versioninfo[0][0];
		_root.revertname  =versioninfo[0][1];
		_root.revertauthor=versioninfo[0][2];
	};

	// Respond to buttons

	function handleHistoryChoice(choice) {
		if (choice==iText('cancel')) { return; }
		getURL("http://www.openstreetmap.org/browse/"+_root.reverttype+"/"+_root.revertid,"_blank");
	};

	function doMail() {
		_root.windows.history.remove();
		if (_root.revertauthor>0) {
			getURL("http://www.openstreetmap.org/message/new/"+_root.revertname,"_blank");
		} else {
			handleError(-1,new Array(iText('error_anonymous')));
		}
	};

	function doRevert() {
		if (_root.windows.history.box.revert._alpha<50) { return; }
		_root.windows.history.remove();
		if (_root.reverttype=='way') {
			_root.undo.append(UndoStack.prototype.undo_changeway,
							  new Array(_root.revertid,deepCopy(_root.map.ways[_root.revertid].path),
													   deepCopy(_root.map.ways[_root.revertid].deletednodes),
													   deepCopy(_root.map.ways[_root.revertid].attr)),
							  iText('action_revertway'));
			_root.map.ways[_root.revertid].loadFromDeleted(_root.reverttime);
		} else if (nodes[_root.revertid]) { // node in way
			noderesponder=function() {};
			noderesponder.onResult=function(result) {
				var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
				var n=result[0];
				_root.nodes[n].attr=result[3];
				var w=_root.nodes[n].moveTo(long2coord(result[1]),lat2coord(result[2]));
				_root.map.ways[w].clean=false;
				_root.map.ways[w].select();
			};
			remote_read.call('getpoi',noderesponder,_root.revertid,_root.reverttime);
		} else { // POI
			_root.map.pois[_root.revertid].clean=false;
			_root.map.pois[_root.revertid].reload(_root.reverttime);
		}
	};


	// getDeleted - load all deleted ways (like whichways), but locked

	function getDeleted() {
		whichdelresponder=function() {};
		whichdelresponder.onResult=function(result) {
			var code=result.shift(); var msg=result.shift(); if (code) { handleError(code,msg,result); return; }
			_root.versioninfo=null;
			waylist=result[0];
			for (i in waylist) {										// ways
				way=waylist[i];											//  |
				if (!_root.map.ways[way]) {								//  |
					_root.map.ways.attachMovie("way",way,++waydepth);	//  |
					_root.map.ways[way].loadFromDeleted('');			//  |
					_root.waycount+=1;									//  |
				}
			}
		};
		remote_read.call('whichways_deleted',whichdelresponder,_root.edge_l,_root.edge_b,_root.edge_r,_root.edge_t);
	};
