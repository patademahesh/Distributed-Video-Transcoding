<?php
include_once ("conn.php");
    $queryAppend = '';
    if (isset($_REQUEST['p']) && $_REQUEST['p'] != '') {
        $queryAppend = " AND cp = '" . $_REQUEST['p'] . "'";
    }

?>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <title>Video Transcoding Farm - Network18</title>
    <meta http-equiv="refresh" content="60">
    <link rel="stylesheet" href="//code.jquery.com/ui/1.11.2/themes/smoothness/jquery-ui.css">
    <script src="//code.jquery.com/jquery-1.10.2.js"></script>
    <script src="//code.jquery.com/ui/1.11.2/jquery-ui.js"></script>
    <link rel="stylesheet" href="/resources/demos/style.css">
    <script>
        $(function() {
            $("#tabs").tabs();
        });

        $(document).ready(function() {
            var status = "INPROCESS";
            var target = "#tabs-1";
            var cp = "";
            setData(cp, status, target);

            $(".tab-list").click(function() {
                status = $(this).attr("status");
                target = $(this).attr("href");
                cp = $("#cp").val();
                setData(cp, status, target);
            });
        });

        function setData(cp, status, target) {
            $.get("ajax.php", {
                p:cp,
                res:status
            }, function(res) {
                $(target).html(res);
            });
        }

	function clearData(status, p, id) {
            $.get("ajax.php", {
		res:status,
		p:p,
                id:id
            }, function(res) {
                $('#tabs-3').html(res);
            });
        }
	
    </script>
</head>
<body>
<input type="hidden" id="cp" value="<?php echo $_REQUEST['p'];?>">

<div id="tabs">
    <ul>
        <li><a href="#tabs-1" class="tab-list" status="INPROCESS">IN PROCESS</a></li>
        <li><a href="#tabs-2" class="tab-list" status="COMPLETED">COMPLETED</a></li>
        <li><a href="#tabs-3" class="tab-list" status="FAILURE">FAILURE</a></li>
    </ul>
    <div id="tabs-1">
<?php
/*    $sql = "SELECT * FROM jobs WHERE job_status < (no_nodes+1) AND node_failed is null AND job_failed is null" . $queryAppend;
    $res = mysqli_query($_Link, $sql);
    while ($rec = mysqli_fetch_array($res)) {
        echo "<div style='color:blue'>" . $rec['name'] . " (" . $rec['cp'] . ") is in Process</div>";
    }
    */?>
    </div>
    <div id="tabs-2">
<?php
/*    $sql = "SELECT * FROM jobs WHERE job_status=(no_nodes+1) AND node_failed is null AND job_failed is null" . $queryAppend;
    $res = mysqli_query($_Link, $sql);
    while ($rec = mysqli_fetch_array($res)) {
        echo "<div style='color:green'>" . $rec['name'] . " (" . $rec['cp'] . ") is Successfully Completed</div>";
    }
    */?>
    </div>
    <div id="tabs-3">
<?php
/*    $sql = "SELECT * FROM jobs WHERE job_status < (no_nodes+1) AND (node_failed is not null or job_failed is not null)" . $queryAppend;
    $res = mysqli_query($_Link, $sql);
    while ($rec = mysqli_fetch_array($res)) {
        echo "<div style='color:red'>" . $rec['name'] . " (" . $rec['cp'] . ") is Failed</div>";
        echo "<ul>";
        if ($rec['node_failed'] != null) {
            echo "<li>" . $rec['node_failed'] . "</li>";
        }
        if ($rec['job_failed'] != null) {
            echo "<li>" . $rec['job_failed'] . "</li>";
        }
        echo "</ul>";
    }


    */?>
    </div>
</div>


</body>
</html>
