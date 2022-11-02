import React from 'react';
import {
  VSCodeBadge,
  VSCodeButton,
  VSCodeDivider,
} from '@vscode/webview-ui-toolkit/react';
import { CmdData } from '../../../types';
import { NODE_HEIGHT, Dims } from '../TreeMapView/TreeMapView';
import NodeWrap from '../TreeMapView/NodeWrap';
import { NodeProps } from 'react-flow-renderer';
import { Code } from '../util';

import './ExecMap.css';

export type ExecMapNodeData =
  | {
      type: 'Cmd';
      cmdData: CmdData;
      isFinal: boolean;
      isCurrentCmd: boolean;
      hasParent: boolean;
      jump: () => void;
    }
  | {
      type: 'Empty';
      hasParent: boolean;
      exec: () => void;
    }
  | {
      type: 'Root';
      procName: string;
    };

const ExecMapNode = ({ data }: NodeProps<ExecMapNodeData & Dims>) => {
  const { type, width, height } = data;
  if (type === 'Empty') {
    return (
      <NodeWrap
        classes={['node-empty']}
        noSourceHandle
        noTargetHandle={!data.hasParent}
        width={width}
        height={height}
      >
        <VSCodeButton
          appearance="icon"
          aria-label="Execute here"
          title="Execute here"
          onClick={data.exec}
        >
          <span className="codicon codicon-play" />
        </VSCodeButton>
      </NodeWrap>
    );
  }

  if (type === 'Root') {
    return (
      <NodeWrap root noTargetHandle width={width} height={height}>
        <span className="node-title">
          <Code>{data.procName}</Code>
        </span>
      </NodeWrap>
    );
  }

  const { cmdData, isFinal, isCurrentCmd, hasParent } = data;

  const unifyBadge = (() => {
    if (cmdData.unifys.length > 0) {
      const [, , [result]] = cmdData.unifys[0];
      const colorStyle = result === 'Success' ? {} : { color: 'red' };
      return (
        <>
          <VSCodeBadge>
            <div
              style={colorStyle}
              className={`codicon codicon-${
                result === 'Success' ? 'pass' : 'error'
              }`}
            />
            &nbsp;
            <div style={colorStyle}>Unify</div>
          </VSCodeBadge>
          &nbsp;
        </>
      );
    } else {
      return <></>;
    }
  })();

  let errorTooltip = <></>;
  if (cmdData.errors.length > 0) {
    errorTooltip = (
      <>
        <VSCodeDivider />
        <div className="tooltip-error">
          <ul>
            {cmdData.errors.map((error, i) => (
              <li key={i}>{error}</li>
            ))}
          </ul>
        </div>
      </>
    );
  }

  const tooltip = (
    <div className="tooltip">
      <Code>{cmdData.display}</Code>
      {errorTooltip}
    </div>
  );

  return (
    <NodeWrap
      selected={isCurrentCmd}
      error={cmdData.errors.length > 0}
      noSourceHandle={isFinal}
      noTargetHandle={!hasParent}
      tooltip={tooltip}
      width={width}
      height={height}
    >
      <pre>{cmdData.display}</pre>
      <div className="node-button-row">
        {unifyBadge}
        <VSCodeButton
          appearance="icon"
          aria-label="Jump here"
          title="Jump here"
          disabled={isCurrentCmd}
          onClick={isCurrentCmd ? undefined : data.jump}
        >
          <span className="codicon codicon-target" />
        </VSCodeButton>
      </div>
    </NodeWrap>
  );
};

export default ExecMapNode;