import {MindAidLlmRequest, MindAidLlmResponse} from "./mind_aid_llm_models";

export interface MindAidLlmProvider {
  generate(request: MindAidLlmRequest): Promise<MindAidLlmResponse>;
}
